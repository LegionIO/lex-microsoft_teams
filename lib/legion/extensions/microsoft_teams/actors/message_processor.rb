# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actors
        class MessageProcessor < Legion::Extensions::Actors::Subscription
          def runner_class    = 'Legion::Extensions::MicrosoftTeams::Runners::Bot'
          def runner_function = 'handle_message'
          def check_subtask?  = false
          def generate_task?  = false

          def enabled?
            defined?(Legion::Extensions::MicrosoftTeams::Runners::Bot) &&
              defined?(Legion::Transport)
          rescue StandardError
            false
          end
        end
      end
    end
  end
end
