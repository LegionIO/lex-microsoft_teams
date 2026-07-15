# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class ApiIngest < Legion::Extensions::Actors::Every
          include Legion::Extensions::MicrosoftTeams::Helpers::ThrottleAware

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
            handle_exception(e, level: :warn, operation: 'ApiIngest#delay')
            14
          end

          def time
            teams_settings.dig(:api_ingest, :interval)
          end

          def enabled?
            teams_settings.dig(:api_ingest, :enabled) &&
              defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'ApiIngest#enabled?')
            false
          end

          def manual
            log.debug('ApiIngest#manual starting')
            # The runner re-raises Errors::Throttled (rather than folding it
            # into an error result) precisely so this actor can defer its
            # next run by the advertised retry_after instead of charging the
            # shared Graph circuit again on the next interval.
            with_throttle_deferral { run_ingest }
          rescue StandardError => e
            handle_exception(e, level: :error, operation: 'ApiIngest#manual')
          end

          private

          def run_ingest
            token = resolve_token
            unless token
              log.warn('ApiIngest: no delegated token, skipping')
              return
            end

            ai_settings = teams_settings[:api_ingest]
            log.info('ApiIngest: starting Graph API ingest')
            result = runner_class.ingest_api(
              token:          token,
              top_people:     ai_settings[:top_people],
              message_depth:  ai_settings[:message_depth],
              skip_bots:      ai_settings[:skip_bots],
              imprint_active: imprint_active?
            )
            log.info("ApiIngest: #{result.inspect[0, 200]}")
            result
          end

          def token_available?
            resolve_token != nil
          end

          def resolve_token
            Legion::Extensions::Identity::Entra::Helpers::TokenManager.load_token(:delegated)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'ApiIngest#resolve_token')
            nil
          end

          def teams_settings
            settings
          end

          def imprint_active?
            return false unless defined?(Legion::Extensions::Coldstart::Helpers::Bootstrap)

            Legion::Extensions::Coldstart::Helpers::Bootstrap.new.imprint_active?
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'ApiIngest#imprint_active?')
            false
          end
        end
      end
    end
  end
end
