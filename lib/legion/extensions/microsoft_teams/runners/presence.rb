# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Presence
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def get_presence(user_id: 'me', **)
            conn = graph_connection(**)
            response = conn.get("#{user_path(user_id)}/presence")
            body = response.body || {}
            {
              availability: body['availability'],
              activity:     body['activity'],
              fetched_at:   Time.now.utc
            }
          rescue StandardError => e
            { availability: 'Offline', activity: 'OffWork', error: e.message, fetched_at: Time.now.utc }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
