# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Meetings
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_meetings(user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings")
            { result: response.body }
          end

          def get_meeting(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}")
            { result: response.body }
          end

          def create_meeting(subject:, start_time:, end_time:, user_id: 'me', **)
            payload = {
              subject:       subject,
              startDateTime: start_time,
              endDateTime:   end_time
            }
            response = graph_connection(**).post("#{user_path(user_id)}/onlineMeetings", payload)
            { result: response.body }
          end

          def update_meeting(meeting_id:, user_id: 'me', subject: nil, start_time: nil, end_time: nil, **)
            payload = {}
            payload[:subject] = subject if subject
            payload[:startDateTime] = start_time if start_time
            payload[:endDateTime] = end_time if end_time
            response = graph_connection(**).patch("#{user_path(user_id)}/onlineMeetings/#{meeting_id}", payload)
            { result: response.body }
          end

          def delete_meeting(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).delete("#{user_path(user_id)}/onlineMeetings/#{meeting_id}")
            { result: response.body }
          end

          def get_meeting_by_join_url(join_url:, user_id: 'me', **)
            params = { '$filter' => "joinWebUrl eq '#{join_url.gsub("'", "''")}'" }
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings", params)
            { result: response.body }
          end

          def list_attendance_reports(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/attendanceReports")
            { result: response.body }
          end

          def get_attendance_report(meeting_id:, report_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/attendanceReports/#{report_id}")
            { result: response.body }
          end

          def resolve_meeting(chat_thread_id: nil, join_url: nil, user_id: 'me', **)
            return { error: 'provide chat_thread_id or join_url' } unless chat_thread_id || join_url

            unless join_url
              chat_response = graph_connection(**).get("chats/#{chat_thread_id}")
              chat_body = chat_response.body
              return { error: 'chat not found', result: chat_body } unless chat_body.is_a?(Hash) && !chat_body.key?('error')

              join_url = chat_body.dig('onlineMeetingInfo', 'joinWebUrl')
              return { error: 'chat has no onlineMeetingInfo', result: chat_body } unless join_url
            end

            meeting_response = get_meeting_by_join_url(join_url: join_url, user_id: user_id, **)
            meeting_body = meeting_response[:result]
            items = meeting_body.is_a?(Hash) ? meeting_body['value'] : nil
            return { error: 'could not resolve meeting from join URL', result: meeting_body } unless items.is_a?(Array) && !items.empty?

            { result: items.first }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
