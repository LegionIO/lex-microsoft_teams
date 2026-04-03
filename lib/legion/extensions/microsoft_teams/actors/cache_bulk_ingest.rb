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
            # TODO: implement run-once-ever via Data::Local flag so bulk ingest
            #       doesn't re-run on every restart
            false
          end

          def manual
            log.info('CacheBulkIngest firing')
            result = runner_class.ingest_cache(**args)
            log.info("Complete: #{result.inspect[0, 200]}")
            result
          rescue StandardError => e
            log.error("CacheBulkIngest error: #{e.message}")
          end

          def args
            { imprint_active: imprint_active? }
          end

          private

          def imprint_active?
            return false unless defined?(Legion::Extensions::Coldstart::Helpers::Bootstrap)

            Legion::Extensions::Coldstart::Helpers::Bootstrap.new.imprint_active?
          rescue StandardError => e
            log.debug("CacheBulkIngest#imprint_active?: #{e.message}")
            false
          end
        end
      end
    end
  end
end
