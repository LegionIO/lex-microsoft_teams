# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module AiInsights
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_meeting_ai_insights(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/aiInsights")
            { result: response.body }
          end

          def get_meeting_ai_insight(meeting_id:, insight_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/aiInsights/#{insight_id}")
            { result: response.body }
          end

          def list_meeting_recordings(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/recordings")
            { result: response.body }
          end

          def get_meeting_recording(meeting_id:, recording_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/recordings/#{recording_id}")
            { result: response.body }
          end

          def list_call_records(top: 50, **)
            response = graph_connection(**).get('communications/callRecords', { '$top' => top })
            { result: response.body }
          end

          def get_call_record(call_id:, **)
            response = graph_connection(**).get("communications/callRecords/#{call_id}")
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
