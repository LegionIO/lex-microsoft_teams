# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Teams
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_joined_teams(user_id: 'me', **)
            response = graph_connection(**).get("/#{user_id}/joinedTeams")
            { result: response.body }
          end

          def get_team(team_id:, **)
            response = graph_connection(**).get("/teams/#{team_id}")
            { result: response.body }
          end

          def list_team_members(team_id:, **)
            response = graph_connection(**).get("/teams/#{team_id}/members")
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
