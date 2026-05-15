# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module AiInsights
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[insight insights summary callrecord recorded]
          end

          definition :list_meeting_ai_insights,
                     desc:          'List AI-generated insights for an online meeting',
                     mcp_prefix:    'teams.list_meeting_ai_insights',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id: { type: 'string' } }, required: ['meeting_id'] },
                     trigger_words: %w[insights summary ai]

          def list_meeting_ai_insights(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/aiInsights")
            { result: response.body }
          end

          definition :get_meeting_ai_insight,
                     desc:          'Get a specific AI insight for an online meeting',
                     mcp_prefix:    'teams.get_meeting_ai_insight',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id: { type: 'string' },
                                                    insight_id: { type: 'string' } },
                                      required:   %w[meeting_id insight_id] },
                     trigger_words: %w[insight details]

          def get_meeting_ai_insight(meeting_id:, insight_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/aiInsights/#{insight_id}")
            { result: response.body }
          end

          definition :list_meeting_recordings,
                     desc:          'List recordings for an online meeting',
                     mcp_prefix:    'teams.list_meeting_recordings',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id: { type: 'string' } }, required: ['meeting_id'] },
                     trigger_words: %w[recordings recorded]

          def list_meeting_recordings(meeting_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/recordings")
            { result: response.body }
          end

          definition :get_meeting_recording,
                     desc:          'Get a specific recording for an online meeting',
                     mcp_prefix:    'teams.get_meeting_recording',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { meeting_id:   { type: 'string' },
                                                    recording_id: { type: 'string' } },
                                      required:   %w[meeting_id recording_id] },
                     trigger_words: %w[recording download]

          def get_meeting_recording(meeting_id:, recording_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/onlineMeetings/#{meeting_id}/recordings/#{recording_id}")
            { result: response.body }
          end

          definition :list_call_records,
                     desc:          'List Teams call records from communications API',
                     mcp_prefix:    'teams.list_call_records',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     trigger_words: %w[records calls history]

          def list_call_records(**)
            response = graph_connection(**).get('communications/callRecords')
            { result: response.body }
          end

          definition :get_call_record,
                     desc:          'Get a specific Teams call record',
                     mcp_prefix:    'teams.get_call_record',
                     mcp_category:  'teams_meetings',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { call_id: { type: 'string' } }, required: ['call_id'] },
                     trigger_words: %w[callrecord record]

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
