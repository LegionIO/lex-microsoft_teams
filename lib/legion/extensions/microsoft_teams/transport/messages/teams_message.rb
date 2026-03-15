# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Transport
        module Messages
          class TeamsMessage < Legion::Transport::Message
            def routing_key = 'teams.messages.process'
            def exchange    = Legion::Extensions::MicrosoftTeams::Transport::Exchanges::Messages
          end
        end
      end
    end
  end
end
