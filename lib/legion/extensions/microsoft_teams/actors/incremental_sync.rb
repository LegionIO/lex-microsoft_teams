# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class IncrementalSync < Legion::Extensions::Actors::Every
          def runner_class    = Legion::Extensions::MicrosoftTeams::Runners::ProfileIngest
          def runner_function = 'incremental_sync'
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false
          def run_now?        = false
          def delay           = 60

          def time
            settings = begin
              Legion::Settings[:microsoft_teams] || {}
            rescue StandardError => e
              handle_exception(e, level: :debug, operation: 'IncrementalSync#time')
              {}
            end
            settings.dig(:ingest, :incremental_interval) || 120
          end

          def enabled?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces) &&
              token_available?
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: 'IncrementalSync#enabled?')
            false
          end

          def manual
            log.debug('IncrementalSync#manual starting')
            token = resolve_token
            return unless token

            settings = begin
              Legion::Settings[:microsoft_teams] || {}
            rescue StandardError => e
              handle_exception(e, level: :debug, operation: 'IncrementalSync#manual settings')
              {}
            end
            ingest = settings[:ingest] || {}
            runner_class.incremental_sync(
              token:         token,
              top_people:    ingest.fetch(:top_people, 10),
              message_depth: ingest.fetch(:message_depth, 50)
            )
          rescue StandardError => e
            handle_exception(e, level: :error, operation: 'IncrementalSync#manual')
          end

          private

          def token_available?
            resolve_token != nil
          end

          def resolve_token
            Legion::Extensions::Identity::Entra::Helpers::TokenManager.load_token(:delegated)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'IncrementalSync#resolve_token')
            nil
          end
        end
      end
    end
  end
end
