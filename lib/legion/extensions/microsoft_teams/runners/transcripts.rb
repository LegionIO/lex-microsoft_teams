# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Transcripts
          extend Legion::Extensions::Definitions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          CONTENT_TYPES = {
            vtt:  'text/vtt',
            docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
          }.freeze

          def self.trigger_words
            %w[transcript transcripts vtt spoken]
          end

          definition :list_transcripts,
                     desc:          'List transcripts for an online meeting with pagination',
                     mcp_prefix:    'teams.list_transcripts',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id: { type: 'string' },
                                                    top:        { type:        'integer',
                                                                  description: 'Transcripts per page (default 50)' },
                                                    max_pages:  { type:        'integer',
                                                                  description: 'Maximum pages to fetch (default 1)' } },
                                      required:   ['meeting_id'] },
                     trigger_words: ['transcripts']

          def list_transcripts(meeting_id:, user_id: 'me', top: 50, max_pages: 1, **)
            params = { '$top' => top }
            conn = graph_connection(**)
            response = conn.get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/transcripts", params)
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

          definition :get_transcript,
                     desc:          'Get metadata for a specific meeting transcript',
                     mcp_prefix:    'teams.get_transcript',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id:    { type: 'string' },
                                                    transcript_id: { type: 'string' } },
                                      required:   %w[meeting_id transcript_id] },
                     trigger_words: %w[transcript details]

          def get_transcript(meeting_id:, transcript_id:, user_id: 'me', **)
            response = graph_connection(**).get(
              "#{user_path(user_id)}/onlineMeetings/#{meeting_id}/transcripts/#{transcript_id}"
            )
            { result: response.body }
          end

          definition :get_transcript_content,
                     desc:          'Download the content of a meeting transcript (VTT or DOCX)',
                     mcp_prefix:    'teams.get_transcript_content',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id:    { type: 'string' },
                                                    transcript_id: { type: 'string' },
                                                    format:        { type:        'string',
                                                                     description: 'Output format: vtt (default) or docx' } },
                                      required:   %w[meeting_id transcript_id] },
                     trigger_words: %w[content vtt text read]

          def get_transcript_content(meeting_id:, transcript_id:, user_id: 'me', format: :vtt, **)
            accept = CONTENT_TYPES.fetch(format)
            response = graph_connection(**).get(
              "#{user_path(user_id)}/onlineMeetings/#{meeting_id}/transcripts/#{transcript_id}/content"
            ) do |req|
              req.headers['Accept'] = accept
            end
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
