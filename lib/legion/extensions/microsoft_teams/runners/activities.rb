# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Activities
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[notification notifications activity alert alerts]
          end

          definition :send_activity_notification,
                     desc:          'Send an activity notification to a Teams user',
                     mcp_prefix:    'teams.send_activity_notification',
                     mcp_category:  'teams_activities',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { topic:         { type:        'string',
                                                                     description: 'Notification topic object' },
                                                    activity_type: { type:        'string',
                                                                     description: 'Activity type registered in app manifest' } },
                                      required:   %w[topic activity_type] },
                     trigger_words: %w[notify notification activity]

          def send_activity_notification(topic:, activity_type:, user_id: 'me', preview_text: nil, **)
            payload = { topic: topic, activityType: activity_type }
            payload[:previewText] = preview_text if preview_text
            response = graph_connection(**).post("#{user_path(user_id)}/teamwork/sendActivityNotification", payload)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
