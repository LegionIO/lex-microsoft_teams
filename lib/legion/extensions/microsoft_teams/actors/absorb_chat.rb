# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class AbsorbChat < Legion::Extensions::Actors::Subscription
          def runner_class    = 'Legion::Extensions::MicrosoftTeams::Absorbers::Chat'
          def runner_function = 'absorb'
          def check_subtask?  = false
          def generate_task?  = false

          def enabled?
            defined?(Legion::Extensions::Absorbers::Base) &&
              defined?(Legion::Extensions::MicrosoftTeams::Absorbers::Chat)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'AbsorbChat#enabled?')
            false
          end

          def work(payload)
            log.debug("AbsorbChat#work payload=#{payload.inspect[0, 100]}")
            parsed   = parse_payload(payload)
            absorber = Absorbers::Chat.new
            result   = absorber.absorb(
              url:      parsed[:url],
              metadata: parsed[:metadata] || {},
              context:  parsed[:context] || {}
            )
            if result.respond_to?(:[]) && result.key?(:success)
              if result[:success]
                ack!
              else
                handle_exception(RuntimeError.new(result.inspect), level:     :error,
                                                                   operation: 'AbsorbChat#work')
                reject!(requeue: false)
              end
            else
              ack!
            end
            result
          rescue StandardError => e
            handle_exception(e, level: :error, operation: 'AbsorbChat#work')
            reject!(requeue: false)
          end

          private

          def parse_payload(payload)
            log.debug('AbsorbChat#parse_payload')
            data = payload.is_a?(String) ? json_load(payload) : payload
            return {} unless data.is_a?(Hash)

            data.transform_keys(&:to_sym)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'AbsorbChat#parse_payload')
            {}
          end
        end
      end
    end
  end
end
