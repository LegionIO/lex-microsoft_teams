# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Meetings
          extend Legion::Extensions::Definitions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[meeting meetings calendar schedule scheduled attendance attendee]
          end

          definition :list_meetings,
                     desc:          'List online meetings for the current user with pagination and filtering',
                     mcp_prefix:    'teams.list_meetings',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :low,
                     idempotent:    true,
                     inputs:        { properties: { top:       { type:        'integer',
                                                                 description: 'Meetings per page (default 50)' },
                                                    max_pages: { type:        'integer',
                                                                 description: 'Maximum pages to fetch (default 1)' },
                                                    filter:    { type:        'string',
                                                                 description: 'OData $filter expression' } },
                                      required:   [] },
                     trigger_words: %w[meetings upcoming calendar]

          def list_meetings(user_id: 'me', top: 50, max_pages: 1, filter: nil, **)
            params = { '$top' => top }
            params['$filter'] = filter if filter
            conn = graph_connection(**)
            response = conn.get("#{user_path(user_id)}/onlineMeetings", params)
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

          definition :get_meeting,
                     desc:          'Get details for a specific online meeting',
                     mcp_prefix:    'teams.get_meeting',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :low,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id: { type: 'string' } }, required: ['meeting_id'] },
                     trigger_words: %w[meeting details]

          def get_meeting(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}")
            { result: response.body }
          end

          definition :create_meeting,
                     desc:          'Create a new online meeting',
                     mcp_prefix:    'teams.create_meeting',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { subject:    { type: 'string' },
                                                    start_time: { type:        'string',
                                                                  description: 'ISO 8601 start datetime' },
                                                    end_time:   { type:        'string',
                                                                  description: 'ISO 8601 end datetime' } },
                                      required:   %w[subject start_time end_time] },
                     trigger_words: %w[create schedule]

          def create_meeting(subject:, start_time:, end_time:, user_id: 'me', **)
            payload = {
              subject:       subject,
              startDateTime: start_time,
              endDateTime:   end_time
            }
            response = graph_connection(**).post("#{user_path(user_id)}/onlineMeetings", payload)
            { result: response.body }
          end

          definition :update_meeting,
                     desc:          'Update an existing online meeting',
                     mcp_prefix:    'teams.update_meeting',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { meeting_id: { type: 'string' } }, required: ['meeting_id'] },
                     trigger_words: %w[update reschedule]

          def update_meeting(meeting_id:, user_id: 'me', subject: nil, start_time: nil, end_time: nil, **)
            payload = {}
            payload[:subject] = subject if subject
            payload[:startDateTime] = start_time if start_time
            payload[:endDateTime] = end_time if end_time
            response = graph_connection(**).patch("#{user_path(user_id)}/onlineMeetings/#{meeting_id}", payload)
            { result: response.body }
          end

          definition :delete_meeting,
                     desc:          'Delete an online meeting',
                     mcp_prefix:    'teams.delete_meeting',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :high,
                     idempotent:    false,
                     inputs:        { properties: { meeting_id: { type: 'string' } }, required: ['meeting_id'] },
                     trigger_words: %w[delete cancel]

          def delete_meeting(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).delete("#{user_path(user_id)}/onlineMeetings/#{meeting_id}")
            { result: response.body }
          end

          definition :get_meeting_by_join_url,
                     desc:          'Look up a meeting by its join URL',
                     mcp_prefix:    'teams.get_meeting_by_join_url',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :low,
                     idempotent:    true,
                     inputs:        { properties: { join_url: { type:        'string',
                                                                description: 'Teams join URL' } },
                                      required:   ['join_url'] },
                     trigger_words: %w[url join find]

          def get_meeting_by_join_url(join_url:, user_id: 'me', **)
            params = { '$filter' => "joinWebUrl eq '#{join_url.gsub("'", "''")}'" }
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings", params)
            { result: response.body }
          end

          definition :list_attendance_reports,
                     desc:          'List attendance reports for an online meeting',
                     mcp_prefix:    'teams.list_attendance_reports',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id: { type: 'string' } }, required: ['meeting_id'] },
                     trigger_words: %w[attendance attendees report]

          def list_attendance_reports(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/attendanceReports")
            { result: response.body }
          end

          definition :get_attendance_report,
                     desc:          'Get a specific attendance report for an online meeting',
                     mcp_prefix:    'teams.get_attendance_report',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id: { type: 'string' },
                                                    report_id:  { type: 'string' } },
                                      required:   %w[meeting_id report_id] },
                     trigger_words: %w[attendance details]

          def get_attendance_report(meeting_id:, report_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/attendanceReports/#{report_id}")
            { result: response.body }
          end

          definition :resolve_meeting,
                     desc:          'Resolve a Teams meeting from a chat thread ID or join URL',
                     mcp_prefix:    'teams.resolve_meeting',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :low,
                     idempotent:    true,
                     trigger_words: %w[resolve find]

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
