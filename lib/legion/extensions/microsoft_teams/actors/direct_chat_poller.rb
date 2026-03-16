# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class DirectChatPoller < Legion::Extensions::Actors::Every
          include Legion::Extensions::MicrosoftTeams::Helpers::Client
          include Legion::Extensions::MicrosoftTeams::Helpers::HighWaterMark

          POLL_INTERVAL = 5

          def initialize(**opts)
            return unless enabled?

            @bot_id = bot_id_from_settings
            super
          end

          def runner_class    = Legion::Extensions::MicrosoftTeams::Runners::Bot
          def runner_function = 'handle_message'
          def time            = settings_interval(:direct_poll_interval, POLL_INTERVAL)
          def run_now?        = false
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def enabled?
            defined?(Legion::Extensions::MicrosoftTeams::Runners::Bot) &&
              defined?(Legion::Transport)
          rescue StandardError
            false
          end

          def token_cache
            @token_cache ||= Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.new
          end

          def manual
            token = token_cache.cached_graph_token
            return unless token

            chats = fetch_bot_chats(token: token)
            chats.each { |chat| poll_chat(chat_id: chat[:id], token: token) }
          rescue StandardError => e
            Legion::Logging.error("DirectChatPoller: #{e.message}") if defined?(Legion::Logging)
          end

          private

          def fetch_bot_chats(token:)
            conn = graph_connection(token: token)
            response = conn.get('/me/chats', { '$filter' => "chatType eq 'oneOnOne'", '$top' => 50 })
            response.body&.dig('value') || []
          end

          def poll_chat(chat_id:, token:)
            conn = graph_connection(token: token)
            response = conn.get("/chats/#{chat_id}/messages",
                                { '$top' => 10, '$orderby' => 'createdDateTime desc' })
            messages = response.body&.dig('value') || []

            new_msgs = new_messages(chat_id: chat_id, messages: normalize_messages(messages))
            new_msgs.reject! { |m| m[:from_id] == @bot_id }
            return if new_msgs.empty?

            new_msgs.each { |msg| publish_message(msg.merge(chat_id: chat_id, mode: :direct)) }
            update_hwm_from_messages(chat_id: chat_id, messages: new_msgs)
          end

          def publish_message(payload)
            Legion::Extensions::MicrosoftTeams::Transport::Messages::TeamsMessage.new.publish(payload)
          rescue StandardError => e
            Legion::Logging.error("DirectChatPoller publish failed: #{e.message}") if defined?(Legion::Logging)
          end

          def normalize_messages(messages)
            messages.map do |m|
              {
                id:              m['id'],
                createdDateTime: m['createdDateTime'],
                text:            m.dig('body', 'content') || '',
                from_id:         m.dig('from', 'user', 'id'),
                from_name:       m.dig('from', 'user', 'displayName'),
                content_type:    m.dig('body', 'contentType') || 'text'
              }
            end
          end

          def bot_id_from_settings
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :bot, :bot_id)
          end

          def settings_interval(key, default)
            return default unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :bot, key) || default
          end
        end
      end
    end
  end
end
