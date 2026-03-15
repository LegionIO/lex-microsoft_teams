# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Presence
          def get_presence(user_id:)
            response = client.get("/users/#{user_id}/presence")
            {
              availability: response['availability'] || response[:availability],
              activity:     response['activity'] || response[:activity],
              fetched_at:   Time.now.utc
            }
          rescue StandardError => e
            { availability: 'Offline', activity: 'OffWork', error: e.message, fetched_at: Time.now.utc }
          end
        end
      end
    end
  end
end
