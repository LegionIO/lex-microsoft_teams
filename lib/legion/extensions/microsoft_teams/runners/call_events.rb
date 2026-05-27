# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module CallEvents
          extend Legion::Extensions::Definitions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[call calls session sessions segment pstn]
          end

          definition :list_call_sessions,
                     desc:          'List sessions for a Teams call record with pagination and expand',
                     mcp_prefix:    'teams.list_call_sessions',
                     mcp_category:  'teams_calls',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { call_id:   { type: 'string' },
                                                    top:       { type:        'integer',
                                                                 description: 'Sessions per page (default 50)' },
                                                    max_pages: { type:        'integer',
                                                                 description: 'Maximum pages to fetch (default 1)' },
                                                    expand:    { type:        'string',
                                                                 description: 'Expand related entities (e.g. segments)' },
                                                    select:    { type:        'string',
                                                                 description: 'Comma-separated fields to return' } },
                                      required:   ['call_id'] },
                     trigger_words: %w[sessions calls records]

          def list_call_sessions(call_id:, top: 50, max_pages: 1, expand: nil, select: nil, **)
            params = { '$top' => top }
            params['$expand'] = expand if expand
            params['$select'] = select if select
            conn = graph_connection(**)
            response = conn.get("communications/callRecords/#{call_id}/sessions", params)
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

          definition :get_call_session,
                     desc:          'Get a specific session from a Teams call record',
                     mcp_prefix:    'teams.get_call_session',
                     mcp_category:  'teams_calls',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { call_id:    { type: 'string' },
                                                    session_id: { type: 'string' } },
                                      required:   %w[call_id session_id] },
                     trigger_words: %w[session call record]

          def get_call_session(call_id:, session_id:, **)
            response = graph_connection(**).get(
              "communications/callRecords/#{call_id}/sessions/#{session_id}"
            )
            { result: response.body }
          end

          definition :list_session_segments,
                     desc:          'List segments for a session in a Teams call record with pagination',
                     mcp_prefix:    'teams.list_session_segments',
                     mcp_category:  'teams_calls',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { call_id:    { type: 'string' },
                                                    session_id: { type: 'string' },
                                                    top:        { type:        'integer',
                                                                  description: 'Segments per page (default 50)' },
                                                    max_pages:  { type:        'integer',
                                                                  description: 'Maximum pages to fetch (default 1)' } },
                                      required:   %w[call_id session_id] },
                     trigger_words: %w[segments pstn]

          def list_session_segments(call_id:, session_id:, top: 50, max_pages: 1, **)
            params = { '$top' => top }
            conn = graph_connection(**)
            response = conn.get(
              "communications/callRecords/#{call_id}/sessions/#{session_id}/segments", params
            )
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
