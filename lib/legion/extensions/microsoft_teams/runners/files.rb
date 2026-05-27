# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Files
          extend Legion::Extensions::Definitions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[file files drive onedrive sharepoint document documents]
          end

          definition :list_drive_items,
                     desc:          'List files in the root of a user\'s OneDrive with pagination and filtering',
                     mcp_prefix:    'teams.list_drive_items',
                     mcp_category:  'teams_files',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { top:       { type:        'integer',
                                                                 description: 'Items per page (default 200)' },
                                                    max_pages: { type:        'integer',
                                                                 description: 'Maximum pages to fetch (default 1)' },
                                                    select:    { type:        'string',
                                                                 description: 'Comma-separated fields to return' },
                                                    filter:    { type:        'string',
                                                                 description: 'OData $filter expression' } },
                                      required:   [] },
                     trigger_words: %w[files drive onedrive]

          def list_drive_items(user_id: 'me', top: 200, max_pages: 1, select: nil, filter: nil, **)
            log.debug "list_drive_items(user_id: #{user_id})"
            params = { '$top' => top }
            params['$select'] = select if select
            params['$filter'] = filter if filter
            conn = graph_connection(**)
            response = conn.get("#{user_path(user_id)}/drive/root/children", params)
            body = response.body

            return { result: body } if max_pages <= 1

            all_values = Array(body['value'] || body[:value])
            next_link = body['@odata.nextLink'] || body[:'@odata.nextLink']
            pages_fetched = 1

            while next_link && pages_fetched < max_pages
              response = conn.get(next_link)
              page_body = response.body
              items = page_body['value'] || page_body[:value]
              all_values.concat(Array(items)) if items
              next_link = page_body['@odata.nextLink'] || page_body[:'@odata.nextLink']
              pages_fetched += 1
            end

            result = { '@odata.context' => body['@odata.context'] || body[:'@odata.context'],
                       'value'          => all_values }
            result['@odata.nextLink'] = next_link if next_link
            { result: result }
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
            log.debug "get_drive_item(item_id: #{item_id}), user_id: #{user_id}"
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
            log.debug "get_drive_item_content(item_id: #{item_id}, user_id: #{user_id})"
            response = graph_connection(**).get("#{user_path(user_id)}/drive/items/#{item_id}/content")
            { result: response.body }
          end

          definition :list_team_drive_items,
                     desc:          'List files in a Team\'s SharePoint document library with pagination',
                     mcp_prefix:    'teams.list_team_drive_items',
                     mcp_category:  'teams_files',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { team_id:   { type: 'string' },
                                                    top:       { type:        'integer',
                                                                 description: 'Items per page (default 200)' },
                                                    max_pages: { type:        'integer',
                                                                 description: 'Maximum pages to fetch (default 1)' },
                                                    select:    { type:        'string',
                                                                 description: 'Comma-separated fields to return' } },
                                      required:   ['team_id'] },
                     trigger_words: %w[sharepoint documents team]

          def list_team_drive_items(team_id:, top: 200, max_pages: 1, select: nil, **)
            log.debug "list_team_drive_items(team_id: #{team_id})"
            params = { '$top' => top }
            params['$select'] = select if select
            conn = graph_connection(**)
            response = conn.get("teams/#{team_id}/drive/root/children", params)
            body = response.body

            return { result: body } if max_pages <= 1

            all_values = Array(body['value'] || body[:value])
            next_link = body['@odata.nextLink'] || body[:'@odata.nextLink']
            pages_fetched = 1

            while next_link && pages_fetched < max_pages
              response = conn.get(next_link)
              page_body = response.body
              items = page_body['value'] || page_body[:value]
              all_values.concat(Array(items)) if items
              next_link = page_body['@odata.nextLink'] || page_body[:'@odata.nextLink']
              pages_fetched += 1
            end

            result = { '@odata.context' => body['@odata.context'] || body[:'@odata.context'],
                       'value'          => all_values }
            result['@odata.nextLink'] = next_link if next_link
            { result: result }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
