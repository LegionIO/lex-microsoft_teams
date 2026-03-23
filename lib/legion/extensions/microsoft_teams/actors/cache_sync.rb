# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class CacheSync < Legion::Extensions::Actors::Every
          SYNC_INTERVAL = 300 # 5 minutes

          def initialize(**opts)
            return unless enabled?

            @last_sync_time = nil
            super
          end

          def runner_class    = Legion::Extensions::MicrosoftTeams::Runners::CacheIngest
          def runner_function = 'ingest_cache'
          def time            = SYNC_INTERVAL
          def run_now?        = false
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def enabled?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          rescue StandardError
            false
          end

          def args
            { since: @last_sync_time, skip_bots: true }
          end

          def manual
            result = runner_class.send(runner_function, since: @last_sync_time, skip_bots: true)
            if result.is_a?(Hash) && result[:result]
              latest = result[:result][:latest_time]
              @last_sync_time = latest if latest
              stored = result[:result][:stored] || 0
              log.info("CacheSync: ingested #{stored} new Teams messages") if stored.positive?
            end
          rescue StandardError => e
            log.error("CacheSync: #{e.message}")
          end
        end
      end
    end
  end
end
