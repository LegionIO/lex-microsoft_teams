# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Activities
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

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
