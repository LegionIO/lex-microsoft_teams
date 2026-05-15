# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Channels
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[channel channels post posts feed]
          end

          definition :list_channels,
                     desc:          'List channels in a Team',
                     mcp_prefix:    'teams.list_channels',
                     mcp_category:  'teams_channels',
                     mcp_tier:      :low,
                     idempotent:    true,
                     inputs:        { properties: { team_id: { type: 'string' } }, required: ['team_id'] },
                     trigger_words: %w[channels list]

          def list_channels(team_id:, **)
            response = graph_connection(**).get("teams/#{team_id}/channels")
            { result: response.body }
          end

          definition :get_channel,
                     desc:          'Get a specific channel in a Team',
                     mcp_prefix:    'teams.get_channel',
                     mcp_category:  'teams_channels',
                     mcp_tier:      :low,
                     idempotent:    true,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' } },
                                      required:   %w[team_id channel_id] },
                     trigger_words: %w[channel details]

          def get_channel(team_id:, channel_id:, **)
            response = graph_connection(**).get("teams/#{team_id}/channels/#{channel_id}")
            { result: response.body }
          end

          definition :create_channel,
                     desc:          'Create a new channel in a Team',
                     mcp_prefix:    'teams.create_channel',
                     mcp_category:  'teams_channels',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { team_id:      { type: 'string' },
                                                    display_name: { type: 'string' } },
                                      required:   %w[team_id display_name] },
                     trigger_words: %w[create channel]

          def create_channel(team_id:, display_name:, description: nil, membership_type: 'standard', **)
            payload = { displayName: display_name, membershipType: membership_type }
            payload[:description] = description if description
            response = graph_connection(**).post("teams/#{team_id}/channels", payload)
            { result: response.body }
          end

          definition :update_channel,
                     desc:          'Update a channel display name or description',
                     mcp_prefix:    'teams.update_channel',
                     mcp_category:  'teams_channels',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' } },
                                      required:   %w[team_id channel_id] },
                     trigger_words: %w[update rename]

          def update_channel(team_id:, channel_id:, display_name: nil, description: nil, **)
            payload = {}
            payload[:displayName] = display_name if display_name
            payload[:description] = description if description
            response = graph_connection(**).patch("teams/#{team_id}/channels/#{channel_id}", payload)
            { result: response.body }
          end

          definition :delete_channel,
                     desc:          'Delete a channel from a Team',
                     mcp_prefix:    'teams.delete_channel',
                     mcp_category:  'teams_channels',
                     mcp_tier:      :high,
                     idempotent:    false,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' } },
                                      required:   %w[team_id channel_id] },
                     trigger_words: %w[delete remove]

          def delete_channel(team_id:, channel_id:, **)
            response = graph_connection(**).delete("teams/#{team_id}/channels/#{channel_id}")
            { result: response.body }
          end

          definition :list_channel_members,
                     desc:          'List members of a channel',
                     mcp_prefix:    'teams.list_channel_members',
                     mcp_category:  'teams_channels',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' } },
                                      required:   %w[team_id channel_id] },
                     trigger_words: %w[members roster]

          def list_channel_members(team_id:, channel_id:, **)
            response = graph_connection(**).get("teams/#{team_id}/channels/#{channel_id}/members")
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
