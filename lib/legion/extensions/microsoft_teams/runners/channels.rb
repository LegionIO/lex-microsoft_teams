# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Channels
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_channels(team_id:, **)
            response = graph_connection(**).get("/teams/#{team_id}/channels")
            { result: response.body }
          end

          def get_channel(team_id:, channel_id:, **)
            response = graph_connection(**).get("/teams/#{team_id}/channels/#{channel_id}")
            { result: response.body }
          end

          def create_channel(team_id:, display_name:, description: nil, membership_type: 'standard', **)
            payload = { displayName: display_name, membershipType: membership_type }
            payload[:description] = description if description
            response = graph_connection(**).post("/teams/#{team_id}/channels", payload)
            { result: response.body }
          end

          def update_channel(team_id:, channel_id:, display_name: nil, description: nil, **)
            payload = {}
            payload[:displayName] = display_name if display_name
            payload[:description] = description if description
            response = graph_connection(**).patch("/teams/#{team_id}/channels/#{channel_id}", payload)
            { result: response.body }
          end

          def delete_channel(team_id:, channel_id:, **)
            response = graph_connection(**).delete("/teams/#{team_id}/channels/#{channel_id}")
            { result: response.body }
          end

          def list_channel_members(team_id:, channel_id:, **)
            response = graph_connection(**).get("/teams/#{team_id}/channels/#{channel_id}/members")
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
