# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Transport
        module Exchanges
          class Messages < Legion::Transport::Exchange
            def exchange_name = 'teams.messages'
          end
        end
      end
    end
  end
end
