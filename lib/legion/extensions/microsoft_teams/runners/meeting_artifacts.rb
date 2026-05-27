# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module MeetingArtifacts
          extend Legion::Extensions::Definitions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[recording recordings whiteboard artifact artifacts]
          end

          definition :list_meeting_artifacts,
                     desc:          'List artifacts (recordings, whiteboards) for an online meeting with pagination',
                     mcp_prefix:    'teams.list_meeting_artifacts',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id: { type: 'string' },
                                                    top:        { type:        'integer',
                                                                  description: 'Artifacts per page (default 50)' },
                                                    max_pages:  { type:        'integer',
                                                                  description: 'Maximum pages to fetch (default 1)' } },
                                      required:   ['meeting_id'] },
                     trigger_words: %w[artifacts recordings whiteboards]

          def list_meeting_artifacts(meeting_id:, user_id: 'me', top: 50, max_pages: 1, **)
            params = { '$top' => top }
            conn = graph_connection(**)
            response = conn.get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/artifacts", params)
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

          definition :get_meeting_artifact,
                     desc:          'Get a specific artifact from an online meeting',
                     mcp_prefix:    'teams.get_meeting_artifact',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id:  { type: 'string' },
                                                    artifact_id: { type: 'string' } },
                                      required:   %w[meeting_id artifact_id] },
                     trigger_words: %w[artifact recording whiteboard download]

          def get_meeting_artifact(meeting_id:, artifact_id:, user_id: 'me', **)
            response = graph_connection(**).get(
              "#{user_path(user_id)}/onlineMeetings/#{meeting_id}/artifacts/#{artifact_id}"
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
