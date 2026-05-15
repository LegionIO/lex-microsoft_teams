# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class ApiIngest < Legion::Extensions::Actors::Every
          def runner_class = Legion::Extensions::MicrosoftTeams::Runners::ApiIngest

          def runner_function = 'ingest_api'

          def use_runner? = false

          def check_subtask? = false

          def generate_task? = false

          def run_now? = true

          def delay
            auth_validator = Legion::Extensions::Identity::Entra::Delegated::Actor::AuthValidator.allocate
            base_delay = auth_validator.respond_to?(:delay) ? auth_validator.delay.to_f : 9.0
            [base_delay + 5.0, 14].max
          rescue StandardError => e
            log.debug("ApiIngest#delay: #{e.message}")
            14
          end

          def time
            interval = teams_settings.dig(:ingest, :api_interval) || 1800
            interval.to_i
          end

          def enabled?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          rescue StandardError => e
            log.warn("ApiIngest#enabled?: #{e.message}")
            false
          end

          def manual
            token = resolve_token
            unless token
              log.warn('ApiIngest: no delegated token, skipping')
              return
            end

            ingest = teams_settings[:ingest] || {}
            log.info('ApiIngest: starting Graph API ingest')
            result = runner_class.ingest_api(
              token:          token,
              top_people:     ingest.fetch(:top_people, 15),
              message_depth:  ingest.fetch(:message_depth, 50),
              skip_bots:      ingest.fetch(:skip_bots, true),
              imprint_active: imprint_active?
            )
            log.info("ApiIngest: #{result.inspect[0, 200]}")
            result
          rescue StandardError => e
            log.error("ApiIngest: #{e.message}")
          end

          private

          def token_available?
            resolve_token != nil
          end

          def resolve_token
            Legion::Extensions::Identity::Entra::Helpers::TokenManager.load_token(:delegated)
          rescue StandardError => e
            log.warn("ApiIngest#resolve_token: #{e.message}")
            nil
          end

          def teams_settings
            return {} unless defined?(Legion::Settings)

            Legion::Settings[:microsoft_teams] || {}
          rescue StandardError => e
            log.warn("ApiIngest#teams_settings: #{e.message}")
            {}
          end

          def imprint_active?
            return false unless defined?(Legion::Extensions::Coldstart::Helpers::Bootstrap)

            Legion::Extensions::Coldstart::Helpers::Bootstrap.new.imprint_active?
          rescue StandardError => e
            log.debug("ApiIngest#imprint_active?: #{e.message}")
            false
          end
        end
      end
    end
  end
end
