# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Files
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[file files drive onedrive sharepoint document documents]
          end

          definition :list_drive_items,
                     desc:          'List files in the root of a user\'s OneDrive',
                     mcp_prefix:    'teams.list_drive_items',
                     mcp_category:  'teams_files',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     trigger_words: %w[files drive onedrive]

          def list_drive_items(user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/drive/root/children")
            { result: response.body }
          end

          definition :get_drive_item,
                     desc:          'Get metadata for a specific OneDrive file or folder',
                     mcp_prefix:    'teams.get_drive_item',
                     mcp_category:  'teams_files',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { item_id: { type: 'string' } }, required: ['item_id'] },
                     trigger_words: %w[file item]

          def get_drive_item(item_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/drive/items/#{item_id}")
            { result: response.body }
          end

          definition :get_drive_item_content,
                     desc:          'Download the content of a OneDrive file',
                     mcp_prefix:    'teams.get_drive_item_content',
                     mcp_category:  'teams_files',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { item_id: { type: 'string' } }, required: ['item_id'] },
                     trigger_words: %w[download content read]

          def get_drive_item_content(item_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/drive/items/#{item_id}/content")
            { result: response.body }
          end

          definition :list_team_drive_items,
                     desc:          'List files in a Team\'s SharePoint document library',
                     mcp_prefix:    'teams.list_team_drive_items',
                     mcp_category:  'teams_files',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { team_id: { type: 'string' } }, required: ['team_id'] },
                     trigger_words: %w[sharepoint documents team]

          def list_team_drive_items(team_id:, **)
            response = graph_connection(**).get("teams/#{team_id}/drive/root/children")
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
