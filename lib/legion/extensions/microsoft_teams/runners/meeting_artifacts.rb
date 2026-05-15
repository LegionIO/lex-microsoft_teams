# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module MeetingArtifacts
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_meeting_artifacts(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/artifacts")
            { result: response.body }
          end

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
