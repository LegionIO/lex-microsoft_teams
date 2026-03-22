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
            defined?(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache)
          rescue StandardError
            false
          end

          def token_cache
            Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.instance
          end

          def manual
            token = token_cache.cached_graph_token
            unless token
              log_debug('No token available, skipping presence poll')
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
              log_debug("Presence unchanged: availability=#{availability}, activity=#{activity}")
            else
              log_info("Presence changed: availability=#{availability}, activity=#{activity}")
              @last_presence = current
            end
          rescue StandardError => e
            log_error("PresencePoller: #{e.message}")
          end

          private

          def log_debug(msg)
            Legion::Logging.debug("[Teams::PresencePoller] #{msg}") if defined?(Legion::Logging)
          end

          def log_info(msg)
            Legion::Logging.info("[Teams::PresencePoller] #{msg}") if defined?(Legion::Logging)
          end

          def log_error(msg)
            Legion::Logging.error("[Teams::PresencePoller] #{msg}") if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
