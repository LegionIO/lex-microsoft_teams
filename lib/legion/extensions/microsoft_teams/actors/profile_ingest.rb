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

          def args
            token = resolve_token
            settings = begin
              Legion::Settings[:microsoft_teams]
            rescue StandardError
              {}
            end
            ingest = settings.dig(:ingest) || {}
            {
              token: token,
              top_people: ingest.fetch(:top_people, 10),
              message_depth: ingest.fetch(:message_depth, 50)
            }
          end

          private

          def token_available?
            resolve_token != nil
          end

          def resolve_token
            if defined?(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache)
              cache = Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.new
              cache.cached_delegated_token
            end
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
