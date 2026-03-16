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

          def list_transcripts(user_id:, meeting_id:, **)
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings/#{meeting_id}/transcripts")
            { result: response.body }
          end

          def get_transcript(user_id:, meeting_id:, transcript_id:, **)
            response = graph_connection(**).get(
              "/users/#{user_id}/onlineMeetings/#{meeting_id}/transcripts/#{transcript_id}"
            )
            { result: response.body }
          end

          def get_transcript_content(user_id:, meeting_id:, transcript_id:, format: :vtt, **)
            accept = CONTENT_TYPES.fetch(format)
            response = graph_connection(**).get(
              "/users/#{user_id}/onlineMeetings/#{meeting_id}/transcripts/#{transcript_id}/content"
            ) do |req|
              req.headers['Accept'] = accept
            end
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
