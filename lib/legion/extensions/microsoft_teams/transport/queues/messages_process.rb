# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Transport
        module Queues
          class MessagesProcess < Legion::Transport::Queue
            def queue_name = 'teams.messages.process'
            def queue_options = { auto_delete: false }
          end
        end
      end
    end
  end
end
