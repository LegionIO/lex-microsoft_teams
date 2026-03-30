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
            if defined?(Legion::Extensions::MicrosoftTeams::Actor::AuthValidator)
              auth_validator = Legion::Extensions::MicrosoftTeams::Actor::AuthValidator.allocate
              base_delay = auth_validator.respond_to?(:delay) ? auth_validator.delay.to_f : 90.0
              base_delay + 5.0
            else
              95.0
            end
          end

          def enabled?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces) &&
              token_available?
          rescue StandardError => e
            log.debug("ProfileIngest#enabled?: #{e.message}")
            false
          end

          def manual
            log.info('ProfileIngest firing')
            token = resolve_token
            unless token
              log.warn('No token available, skipping')
              return
            end
            log.info('Token acquired, starting ingest')

            settings = begin
              Legion::Settings[:microsoft_teams] || {}
            rescue StandardError => e
              log.debug("ProfileIngest#manual settings: #{e.message}")
              {}
            end
            ingest = settings[:ingest] || {}
            runner_class.full_ingest(
              token:         token,
              top_people:    ingest.fetch(:top_people, 10),
              message_depth: ingest.fetch(:message_depth, 50)
            )
          rescue StandardError => e
            log.error("ProfileIngest: #{e.message}")
          end

          private

          def token_available?
            resolve_token != nil
          end

          def resolve_token
            if defined?(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache)
              Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.instance.cached_delegated_token
            end
          rescue StandardError => e
            log.warn("ProfileIngest#resolve_token: #{e.message}")
            nil
          end
        end
      end
    end
  end
end
