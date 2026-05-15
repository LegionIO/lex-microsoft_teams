# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class ProfileIngest < Legion::Extensions::Actors::Once
          def runner_class    = Legion::Extensions::MicrosoftTeams::Runners::ProfileIngest
          def runner_function = 'full_ingest'
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def delay
            auth_validator = Legion::Extensions::Identity::Entra::Delegated::Actor::AuthValidator.allocate
            base_delay = auth_validator.respond_to?(:delay) ? auth_validator.delay.to_f : 9.0
            base_delay + 5.0
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: 'ProfileIngest#delay')
            14.0
          end

          def enabled?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces) &&
              token_available?
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: 'ProfileIngest#enabled?')
            false
          end

          def manual
            log.info('ProfileIngest firing')
            token = resolve_token
            unless token
              log.warn('ProfileIngest: no token available, skipping')
              return
            end
            log.info('ProfileIngest: token acquired, starting ingest')

            settings = begin
              Legion::Settings[:microsoft_teams] || {}
            rescue StandardError => e
              handle_exception(e, level: :debug, operation: 'ProfileIngest#manual settings')
              {}
            end
            ingest = settings[:ingest] || {}
            runner_class.full_ingest(
              token:         token,
              top_people:    ingest.fetch(:top_people, 10),
              message_depth: ingest.fetch(:message_depth, 50)
            )
          rescue StandardError => e
            handle_exception(e, level: :error, operation: 'ProfileIngest#manual')
          end

          private

          def token_available?
            resolve_token != nil
          end

          def resolve_token
            Legion::Extensions::Identity::Entra::Helpers::TokenManager.load_token(:delegated)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'ProfileIngest#resolve_token')
            nil
          end
        end
      end
    end
  end
end
