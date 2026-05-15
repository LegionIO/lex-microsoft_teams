# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Transcripts
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          CONTENT_TYPES = {
            vtt:  'text/vtt',
            docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
          }.freeze

          def self.trigger_words
            ['transcript', 'transcripts', 'meeting transcript']
          end

          definition :list_transcripts,
                     desc:          'List transcripts for an online meeting',
                     mcp_prefix:    'teams.list_transcripts',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id: { type: 'string' } }, required: ['meeting_id'] },
                     trigger_words: ['list transcripts', 'meeting transcripts']

          def list_transcripts(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/transcripts")
            { result: response.body }
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
                     trigger_words: ['get transcript', 'transcript details']

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
                                                    transcript_id: { type: 'string' } },
                                      required:   %w[meeting_id transcript_id] },
                     trigger_words: ['get transcript content', 'read transcript', 'vtt', 'transcript text']

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
