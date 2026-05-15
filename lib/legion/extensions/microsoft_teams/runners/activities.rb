# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Activities
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_activity_feed(user_id: 'me', top: 50, **)
            params = { '$top' => top }
            response = graph_connection(**).get("#{user_path(user_id)}/teamwork/installedApps", params)
            { result: response.body }
          end

          def send_activity_notification(user_id:, topic:, activity_type:, preview_text: nil, **)
            payload = { topic: topic, activityType: activity_type }
            payload[:previewText] = preview_text if preview_text
            response = graph_connection(**).post("users/#{user_id}/teamwork/sendActivityNotification", payload)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
