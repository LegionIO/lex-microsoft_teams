# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class MessageProcessor < Legion::Extensions::Actors::Subscription
          def runner_class    = 'Legion::Extensions::MicrosoftTeams::Runners::Bot'
          def runner_function = 'dispatch_message'
          def check_subtask?  = false
          def generate_task?  = false

          def enabled?
            defined?(Legion::Extensions::MicrosoftTeams::Runners::Bot) &&
              Legion.const_defined?(:Transport, false)
          rescue StandardError => e
            log.debug("MessageProcessor#enabled?: #{e.message}")
            false
          end
        end
      end
    end
  end
end
