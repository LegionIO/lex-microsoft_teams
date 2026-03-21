# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Ownership
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          TEAMS_FILTER = "resourceProvisioningOptions/Any(x:x eq 'Team')"
          TEAMS_SELECT = 'id,displayName,mail'
          OWNERS_SELECT = 'id,displayName,mail'

          def sync_owners(team_id: nil, **)
            conn = graph_connection(**)
            if team_id
              owners = fetch_owners(conn: conn, team_id: team_id)
              { owners: owners, team_count: 1, synced_at: Time.now.utc.iso8601 }
            else
              teams = fetch_all_teams(conn: conn)
              all_owners = teams.flat_map do |team|
                fetch_owners(conn: conn, team_id: team['id']).map { |o| o.merge('team_id' => team['id']) }
              end
              { owners: all_owners, team_count: teams.length, synced_at: Time.now.utc.iso8601 }
            end
          rescue StandardError => e
            { error: e.message }
          end

          def detect_orphans(**)
            conn = graph_connection(**)
            teams = fetch_all_teams(conn: conn)
            orphaned = []

            teams.each do |team|
              owners = fetch_owners(conn: conn, team_id: team['id'])
              orphaned << { id: team['id'], display_name: team['displayName'], mail: team['mail'] } if owners.empty?
            end

            { orphaned_teams: orphaned, total_scanned: teams.length, orphan_count: orphaned.length }
          rescue StandardError => e
            { error: e.message }
          end

          def get_team_owners(team_id:, **)
            conn = graph_connection(**)
            owners = fetch_owners(conn: conn, team_id: team_id)
            { team_id: team_id, owners: owners }
          rescue StandardError => e
            { error: e.message }
          end

          private

          def fetch_all_teams(conn:)
            params = { '$filter' => TEAMS_FILTER, '$select' => TEAMS_SELECT }
            resp = conn.get('groups', params)
            (resp.body || {}).fetch('value', [])
          end

          def fetch_owners(conn:, team_id:)
            params = { '$select' => OWNERS_SELECT }
            resp = conn.get("groups/#{team_id}/owners", params)
            (resp.body || {}).fetch('value', [])
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
