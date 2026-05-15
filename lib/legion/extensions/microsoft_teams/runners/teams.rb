# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Teams
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[team teams workspace group membership]
          end

          definition :list_joined_teams,
                     desc:          'List Teams the current user has joined',
                     mcp_prefix:    'teams.list_joined_teams',
                     mcp_category:  'teams_teams',
                     mcp_tier:      :low,
                     idempotent:    true,
                     trigger_words: %w[teams joined membership]

          def list_joined_teams(user_id: 'me', **)
            response = graph_connection(**).get("#{user_path(user_id)}/joinedTeams")
            { result: response.body }
          end

          definition :get_team,
                     desc:          'Get details for a specific Team by ID',
                     mcp_prefix:    'teams.get_team',
                     mcp_category:  'teams_teams',
                     mcp_tier:      :low,
                     idempotent:    true,
                     inputs:        { properties: { team_id: { type: 'string' } }, required: ['team_id'] },
                     trigger_words: %w[team details workspace]

          def get_team(team_id:, **)
            response = graph_connection(**).get("teams/#{team_id}")
            { result: response.body }
          end

          definition :list_team_members,
                     desc:          'List members of a Team',
                     mcp_prefix:    'teams.list_team_members',
                     mcp_category:  'teams_teams',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { team_id: { type: 'string' } }, required: ['team_id'] },
                     trigger_words: %w[members roster]

          def list_team_members(team_id:, **)
            response = graph_connection(**).get("teams/#{team_id}/members")
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
