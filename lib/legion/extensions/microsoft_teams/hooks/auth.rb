# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Hooks
        class Auth < Legion::Extensions::Hooks::Base # rubocop:disable Legion/Extension/HookMissingRunnerClass
          mount '/callback'

          def self.runner_class
            'Legion::Extensions::MicrosoftTeams::Runners::Auth'
          end
        end
      end
    end
  end
end
