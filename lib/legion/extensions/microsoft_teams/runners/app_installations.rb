# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module AppInstallations
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_installed_apps_for_user(user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/teamwork/installedApps")
            { result: response.body }
          end

          def list_installed_apps_in_chat(chat_id:, **)
            response = graph_connection(**).get("chats/#{chat_id}/installedApps")
            { result: response.body }
          end

          def install_app_for_user(app_id:, user_id: 'me', **)
            payload = {
              'teamsApp@odata.bind' => "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/#{app_id}"
            }
            response = graph_connection(**).post("#{user_path(user_id)}/teamwork/installedApps", payload)
            { result: response.body }
          end

          def uninstall_app_for_user(installation_id:, user_id: 'me', **)
            response = graph_connection(**).delete(
              "#{user_path(user_id)}/teamwork/installedApps/#{installation_id}"
            )
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
