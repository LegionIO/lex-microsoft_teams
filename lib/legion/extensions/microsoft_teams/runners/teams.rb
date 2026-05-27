# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Teams
          extend Legion::Extensions::Definitions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[team teams workspace group membership]
          end

          definition :list_joined_teams,
                     desc:          'List Teams the current user has joined with optional filtering and select',
                     mcp_prefix:    'teams.list_joined_teams',
                     mcp_category:  'teams_teams',
                     mcp_tier:      :low,
                     idempotent:    true,
                     inputs:        { properties: { filter: { type:        'string',
                                                              description: 'OData $filter expression' },
                                                    select: { type:        'string',
                                                              description: 'Comma-separated fields to return' } },
                                      required:   [] },
                     trigger_words: %w[teams joined membership]

          def list_joined_teams(user_id: 'me', filter: nil, select: nil, **)
            params = {}
            params['$filter'] = filter if filter
            params['$select'] = select if select
            response = graph_connection(**).get("#{user_path(user_id)}/joinedTeams", params)
            { result: response.body }
          end

          definition :get_team,
                     desc:          'Get details for a specific Team by ID',
                     mcp_prefix:    'teams.get_team',
                     mcp_category:  'teams_teams',
                     mcp_tier:      :low,
                     idempotent:    true,
                     inputs:        { properties: { team_id: { type: 'string' } }, required: ['team_id'] },
                     trigger_words: %w[team details workspace]

          def get_team(team_id:, **)
            response = graph_connection(**).get("teams/#{team_id}")
            { result: response.body }
          end

          definition :list_team_members,
                     desc:          'List members of a Team with pagination',
                     mcp_prefix:    'teams.list_team_members',
                     mcp_category:  'teams_teams',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { team_id:   { type: 'string' },
                                                    top:       { type:        'integer',
                                                                 description: 'Members per page (default 100)' },
                                                    max_pages: { type:        'integer',
                                                                 description: 'Maximum pages to fetch (default 1)' },
                                                    filter:    { type:        'string',
                                                                 description: 'OData $filter expression' } },
                                      required:   ['team_id'] },
                     trigger_words: %w[members roster]

          def list_team_members(team_id:, top: 100, max_pages: 1, filter: nil, **)
            params = { '$top' => top }
            params['$filter'] = filter if filter
            conn = graph_connection(**)
            response = conn.get("teams/#{team_id}/members", params)
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
