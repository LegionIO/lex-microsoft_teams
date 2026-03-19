# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Hooks
        class Auth < Legion::Extensions::Hooks::Base
          mount '/callback'

          def route(_headers, _payload)
            :auth_callback
          end

          def runner_class
            'Legion::Extensions::MicrosoftTeams::Runners::Auth'
          end
        end
      end
    end
  end
end
