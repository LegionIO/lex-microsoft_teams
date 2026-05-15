# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class PresencePoller < Legion::Extensions::Actors::Every
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          DEFAULT_POLL_INTERVAL = 60

          def runner_class    = self.class
          def runner_function = 'manual'
          def run_now?        = false
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def time
            return DEFAULT_POLL_INTERVAL unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :presence, :poll_interval) || DEFAULT_POLL_INTERVAL
          end

          def enabled?
            Legion::Extensions::Identity::Entra::Helpers::TokenManager.respond_to?(:load_token)
          rescue StandardError => e
            log.debug("PresencePoller#enabled?: #{e.message}")
            false
          end

          def manual
            token = delegated_token
            unless token
              log.debug('No token available, skipping presence poll')
              return
            end

            conn = graph_connection(token: token)
            response = conn.get("#{user_path}/presence")
            presence = response.body
            return unless presence.is_a?(Hash)

            availability = presence['availability']
            activity = presence['activity']
            current = { availability: availability, activity: activity }

            if current == @last_presence
              log.debug("Presence unchanged: availability=#{availability}, activity=#{activity}")
            else
              log.info("Presence changed: availability=#{availability}, activity=#{activity}")
              @last_presence = current
            end
          rescue StandardError => e
            log.error("PresencePoller: #{e.message}")
          end

          private

          def delegated_token
            Legion::Extensions::Identity::Entra::Helpers::TokenManager.load_token(:delegated)
          rescue StandardError => e
            log.warn("PresencePoller#delegated_token: #{e.message}")
            nil
          end
        end
      end
    end
  end
end
