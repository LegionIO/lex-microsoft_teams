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
            5.0
          end

          def enabled?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces) &&
              token_available?
          rescue StandardError
            false
          end

          def manual
            Legion::Logging.info('[Teams::ProfileIngest] ProfileIngest firing') if defined?(Legion::Logging)
            token = resolve_token
            unless token
              Legion::Logging.warn('[Teams::ProfileIngest] No token available, skipping') if defined?(Legion::Logging)
              return
            end
            Legion::Logging.info('[Teams::ProfileIngest] Token acquired, starting ingest') if defined?(Legion::Logging)

            settings = begin
              Legion::Settings[:microsoft_teams] || {}
            rescue StandardError
              {}
            end
            ingest = settings[:ingest] || {}
            runner_class.full_ingest(
              token:         token,
              top_people:    ingest.fetch(:top_people, 10),
              message_depth: ingest.fetch(:message_depth, 50)
            )
          rescue StandardError => e
            Legion::Logging.error("ProfileIngest: #{e.message}") if defined?(Legion::Logging)
          end

          private

          def token_available?
            resolve_token != nil
          end

          def resolve_token
            if defined?(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache)
              Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.instance.cached_delegated_token
            end
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
