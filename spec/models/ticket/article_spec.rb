require 'rails_helper'
require 'models/application_model_examples'
require 'models/concerns/can_be_imported_examples'

RSpec.describe Ticket::Article, type: :model do
  it_behaves_like 'ApplicationModel'
  it_behaves_like 'CanBeImported'

  describe '.create' do
    it 'handles NULL byte in subject or body' do
      expect(create(:ticket_article, subject: "com test 1\u0000", body: "some\u0000message 123"))
        .to be_persisted
    end
  end

  describe 'hooks on creation' do
    context 'of outgoing article' do
      context 'over Twitter' do
        subject!(:twitter_article) { create(:twitter_article, sender_name: 'Agent') }
        let(:channel)              { Channel.find(twitter_article.ticket.preferences[:channel_id]) }

        describe 'background job actions' do
          let(:run_bg_jobs) do
            lambda do
              VCR.use_cassette(cassette, match_requests_on: %i[method uri oauth_headers]) do
                Scheduler.worker(true)
              end
            end
          end

          let(:cassette) { 'models/channel/driver/twitter/article_to_tweet' }

          it 'sets #from attribute to sender’s Twitter handle' do
            expect(&run_bg_jobs)
              .to change { twitter_article.reload.from }
              .to('@example')
          end

          it 'sets #to attribute to recipient’s Twitter handle' do
            expect(&run_bg_jobs)
              .to change { twitter_article.reload.to }
              .to('') # Tweet in VCR cassette is addressed to no one
          end

          it 'sets #message_id attribute to tweet ID (https://twitter.com/statuses/<id>)' do
            expect(&run_bg_jobs)
              .to change { twitter_article.reload.message_id }
              .to('1069382411899817990')
          end

          it 'sets #preferences hash with tweet metadata' do
            expect(&run_bg_jobs)
              .to change { twitter_article.reload.preferences }
              .to(hash_including('twitter', 'links'))

            expect(twitter_article.preferences[:links].first)
              .to include(
                'name'   => 'on Twitter',
                'target' => '_blank',
                'url'    => "https://twitter.com/statuses/#{twitter_article.message_id}"
              )
          end

          it 'does not change #cc attribute' do
            expect(&run_bg_jobs).not_to change { twitter_article.reload.cc }
          end

          it 'does not change #subject attribute' do
            expect(&run_bg_jobs).not_to change { twitter_article.reload.subject }
          end

          it 'does not change #content_type attribute' do
            expect(&run_bg_jobs).not_to change { twitter_article.reload.content_type }
          end

          it 'does not change #body attribute' do
            expect(&run_bg_jobs).not_to change { twitter_article.reload.body }
          end

          it 'does not change #sender association' do
            expect(&run_bg_jobs).not_to change { twitter_article.reload.sender }
          end

          it 'does not change #type association' do
            expect(&run_bg_jobs).not_to change { twitter_article.reload.type }
          end

          it 'sets appropriate status attributes on the ticket’s channel' do
            expect(&run_bg_jobs)
              .to change { channel.reload.attributes }
              .to hash_including(
                'status_in'    => nil,
                'last_log_in'  => nil,
                'status_out'   => 'ok',
                'last_log_out' => ''
              )
          end

          context 'when the original channel (specified in ticket.preferences) was deleted' do
            context 'but a new one with the same screen_name exists' do
              let(:cassette)    { 'models/channel/driver/twitter/article_to_tweet_channel_replace' }
              let(:new_channel) { create(:twitter_channel) }

              before do
                channel.destroy

                expect(new_channel.options[:user][:screen_name])
                  .to eq(channel.options[:user][:screen_name])
              end

              it 'sets appropriate status attributes on the new channel' do
                expect(&run_bg_jobs)
                  .to change { new_channel.reload.attributes }
                  .to hash_including(
                    'status_in'    => nil,
                    'last_log_in'  => nil,
                    'status_out'   => 'ok',
                    'last_log_out' => ''
                  )
              end
            end
          end
        end
      end
    end
  end
end
