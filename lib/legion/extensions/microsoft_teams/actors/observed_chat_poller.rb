# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class ObservedChatPoller < Legion::Extensions::Actors::Every
          include Legion::Extensions::MicrosoftTeams::Helpers::Client
          include Legion::Extensions::MicrosoftTeams::Helpers::HighWaterMark

          POLL_INTERVAL = 30

          def initialize(**opts)
            return unless enabled?

            super
          end

          def runner_class    = Legion::Extensions::MicrosoftTeams::Runners::Bot
          def runner_function = 'observe_message'
          def time            = settings_interval(:observe_poll_interval, POLL_INTERVAL)
          def delay           = 180
          def run_now?        = false
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def enabled?
            return false unless defined?(Legion::Extensions::MicrosoftTeams::Runners::Bot)
            return false unless Legion.const_defined?(:Transport, false)
            return false unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :bot, :observe, :enabled) == true
          rescue StandardError => e
            log.debug("ObservedChatPoller#enabled?: #{e.message}")
            false
          end

          def token_cache
            Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.instance
          end

          def subscription_registry
            @subscription_registry ||= Legion::Extensions::MicrosoftTeams::Helpers::SubscriptionRegistry.new
          end

          def manual
            token = token_cache.cached_app_token
            return unless token

            subscriptions = subscription_registry.active_subscriptions
            subscriptions.each do |sub|
              poll_observed_chat(
                chat_id: sub[:chat_id], owner_id: sub[:owner_id],
                peer_name: sub[:peer_name], token: token
              )
            end
          rescue StandardError => e
            log.error("ObservedChatPoller: #{e.message}")
          end

          private

          def poll_observed_chat(chat_id:, owner_id:, peer_name:, token:)
            conn = graph_connection(token: token)
            response = conn.get("chats/#{chat_id}/messages",
                                { '$top' => 10, '$orderby' => 'createdDateTime desc' })
            messages = response.body&.dig('value') || []

            new_msgs = new_messages(chat_id: chat_id, messages: normalize_messages(messages))
            return if new_msgs.empty?

            new_msgs.each do |msg|
              publish_message(msg.merge(
                                chat_id:   chat_id,
                                mode:      :observe,
                                owner_id:  owner_id,
                                peer_name: peer_name,
                                function:  'observe_message'
                              ))
            end
            update_hwm_from_messages(chat_id: chat_id, messages: new_msgs)
          end

          def publish_message(payload)
            Legion::Extensions::MicrosoftTeams::Transport::Messages::TeamsMessage.new.publish(payload)
          rescue StandardError => e
            log.error("ObservedChatPoller publish failed: #{e.message}")
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

          def settings_interval(key, default)
            return default unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :bot, key) || default
          end
        end
      end
    end
  end
end
