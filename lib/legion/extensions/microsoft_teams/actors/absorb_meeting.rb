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

          def work(payload)
            parsed = parse_payload(payload)
            absorber = Absorbers::Meeting.new
            result   = absorber.absorb(
              url:      parsed[:url],
              metadata: parsed[:metadata] || {},
              context:  parsed[:context] || {}
            )
            ack!
            result
          rescue StandardError => e
            Legion::Logging.error("AbsorbMeeting actor error: #{e.message}") if defined?(Legion::Logging)
            reject!(requeue: false)
          end

          private

          def parse_payload(payload)
            data = payload.is_a?(String) ? Legion::JSON.load(payload) : payload
            data.is_a?(Hash) ? data : {}
          rescue StandardError
            {}
          end
        end
      end
    end
  end
end
