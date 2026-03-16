# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Meetings
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_meetings(user_id:, **)
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings")
            { result: response.body }
          end

          def get_meeting(user_id:, meeting_id:, **)
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings/#{meeting_id}")
            { result: response.body }
          end

          def create_meeting(user_id:, subject:, start_time:, end_time:, **)
            payload = {
              subject:       subject,
              startDateTime: start_time,
              endDateTime:   end_time
            }
            response = graph_connection(**).post("/users/#{user_id}/onlineMeetings", payload)
            { result: response.body }
          end

          def update_meeting(user_id:, meeting_id:, subject: nil, start_time: nil, end_time: nil, **)
            payload = {}
            payload[:subject] = subject if subject
            payload[:startDateTime] = start_time if start_time
            payload[:endDateTime] = end_time if end_time
            response = graph_connection(**).patch("/users/#{user_id}/onlineMeetings/#{meeting_id}", payload)
            { result: response.body }
          end

          def delete_meeting(user_id:, meeting_id:, **)
            response = graph_connection(**).delete("/users/#{user_id}/onlineMeetings/#{meeting_id}")
            { result: response.body }
          end

          def get_meeting_by_join_url(user_id:, join_url:, **)
            params = { '$filter' => "joinWebUrl eq '#{join_url}'" }
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings", params)
            { result: response.body }
          end

          def list_attendance_reports(user_id:, meeting_id:, **)
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings/#{meeting_id}/attendanceReports")
            { result: response.body }
          end

          def get_attendance_report(user_id:, meeting_id:, report_id:, **)
            response = graph_connection(**).get("/users/#{user_id}/onlineMeetings/#{meeting_id}/attendanceReports/#{report_id}")
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
