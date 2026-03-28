# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class AbsorbMeeting < Legion::Extensions::Actors::Subscription
          def runner_class    = 'Legion::Extensions::MicrosoftTeams::Absorbers::Meeting'
          def runner_function = 'absorb'
          def check_subtask?  = false
          def generate_task?  = false

          def enabled?
            defined?(Legion::Extensions::Absorbers::Base) &&
              defined?(Legion::Extensions::MicrosoftTeams::Absorbers::Meeting)
          rescue StandardError => e
            log.debug("AbsorbMeeting#enabled?: #{e.message}")
            false
          end

          def work(payload)
            parsed   = parse_payload(payload)
            absorber = Absorbers::Meeting.new
            result   = absorber.absorb(
              url:      parsed[:url],
              metadata: parsed[:metadata] || {},
              context:  parsed[:context] || {}
            )
            if result.respond_to?(:[]) && result.key?(:success)
              if result[:success]
                ack!
              else
                log.error("AbsorbMeeting actor absorb failed: #{result.inspect}")
                reject!(requeue: false)
              end
            else
              ack!
            end
            result
          rescue StandardError => e
            log.error("AbsorbMeeting actor error: #{e.message}")
            reject!(requeue: false)
          end

          private

          def parse_payload(payload)
            data = payload.is_a?(String) ? json_load(payload) : payload
            return {} unless data.is_a?(Hash)

            data.transform_keys(&:to_sym)
          rescue StandardError => e
            log.debug("AbsorbMeeting#parse_payload: #{e.message}")
            {}
          end
        end
      end
    end
  end
end
