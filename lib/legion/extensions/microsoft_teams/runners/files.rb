# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Files
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_drive_items(user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/drive/root/children")
            { result: response.body }
          end

          def get_drive_item(item_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/drive/items/#{item_id}")
            { result: response.body }
          end

          def get_drive_item_content(item_id:, user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/drive/items/#{item_id}/content")
            { result: response.body }
          end

          def list_team_drive_items(team_id:, **)
            response = graph_connection(**).get("teams/#{team_id}/drive/root/children")
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
