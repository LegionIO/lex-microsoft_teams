# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module AppInstallations
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[app apps addon addons installation installed]
          end

          definition :list_installed_apps_for_user,
                     desc:          'List Teams apps installed for a user',
                     mcp_prefix:    'teams.list_installed_apps_for_user',
                     mcp_category:  'teams_apps',
                     mcp_tier:      :low,
                     idempotent:    true,
                     trigger_words: %w[apps installed]

          def list_installed_apps_for_user(user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/teamwork/installedApps")
            { result: response.body }
          end

          definition :list_installed_apps_in_chat,
                     desc:          'List Teams apps installed in a specific chat',
                     mcp_prefix:    'teams.list_installed_apps_in_chat',
                     mcp_category:  'teams_apps',
                     mcp_tier:      :low,
                     idempotent:    true,
                     inputs:        { properties: { chat_id: { type: 'string' } }, required: ['chat_id'] },
                     trigger_words: %w[apps chat]

          def list_installed_apps_in_chat(chat_id:, **)
            response = graph_connection(**).get("chats/#{chat_id}/installedApps")
            { result: response.body }
          end

          definition :install_app_for_user,
                     desc:          'Install a Teams app for a user',
                     mcp_prefix:    'teams.install_app_for_user',
                     mcp_category:  'teams_apps',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { app_id: { type:        'string',
                                                              description: 'Teams app catalog ID' } },
                                      required:   ['app_id'] },
                     trigger_words: %w[install add app]

          def install_app_for_user(app_id:, user_id: 'me', **)
            payload = {
              'teamsApp@odata.bind' => "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/#{app_id}"
            }
            response = graph_connection(**).post("#{user_path(user_id)}/teamwork/installedApps", payload)
            { result: response.body }
          end

          definition :uninstall_app_for_user,
                     desc:          'Uninstall a Teams app for a user',
                     mcp_prefix:    'teams.uninstall_app_for_user',
                     mcp_category:  'teams_apps',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { installation_id: { type: 'string' } },
                                      required:   ['installation_id'] },
                     trigger_words: %w[uninstall remove]

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
