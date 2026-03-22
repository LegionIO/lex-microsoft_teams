# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class CacheBulkIngest < Legion::Extensions::Actors::Once
          def runner_class    = Legion::Extensions::MicrosoftTeams::Runners::CacheIngest
          def runner_function = 'ingest_cache'
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def delay
            3.0 # give lex-memory a moment to initialize
          end

          def enabled?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          rescue StandardError
            false
          end

          def args
            { imprint_active: imprint_active? }
          end

          private

          def imprint_active?
            return false unless defined?(Legion::Extensions::Coldstart::Helpers::Bootstrap)

            Legion::Extensions::Coldstart::Helpers::Bootstrap.new.imprint_active?
          rescue StandardError
            false
          end
        end
      end
    end
  end
end
