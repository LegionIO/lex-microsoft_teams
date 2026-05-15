# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module MeetingArtifacts
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            ['artifact', 'recording', 'whiteboard', 'meeting file']
          end

          definition :list_meeting_artifacts,
                     desc:          'List artifacts (recordings, whiteboards) for an online meeting',
                     mcp_prefix:    'teams.list_meeting_artifacts',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id: { type: 'string' } }, required: ['meeting_id'] },
                     trigger_words: ['list artifacts', 'meeting recordings', 'meeting files', 'whiteboards']

          def list_meeting_artifacts(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/artifacts")
            { result: response.body }
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
                     trigger_words: ['get artifact', 'download recording', 'get whiteboard']

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
