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

          def list_transcripts(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/transcripts")
            { result: response.body }
          end

          def get_transcript(meeting_id:, transcript_id:, user_id: 'me', **)
            response = graph_connection(**).get(
              "#{user_path(user_id)}/onlineMeetings/#{meeting_id}/transcripts/#{transcript_id}"
            )
            { result: response.body }
          end

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
