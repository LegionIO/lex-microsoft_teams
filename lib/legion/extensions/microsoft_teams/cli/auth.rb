# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/browser_auth'
require 'legion/extensions/microsoft_teams/helpers/token_cache'

module Legion
  module Extensions
    module MicrosoftTeams
      module CLI
        class Auth
          def self.cli_alias
            'teams'
          end

          def self.descriptions
            {
              login:  'Authenticate with Microsoft Teams via browser OAuth',
              status: 'Show current Teams authentication state'
            }
          end

          def login(tenant_id: nil, client_id: nil)
            settings = resolve_settings
            tid = tenant_id || settings[:tenant_id]
            cid = client_id || settings[:client_id]

            unless tid && cid
              puts 'Error: tenant_id and client_id required (set in settings or pass as args)'
              return
            end

            browser_auth = Helpers::BrowserAuth.new(tenant_id: tid, client_id: cid)
            result = browser_auth.authenticate

            if result&.dig(:access_token)
              store_token(result)
              puts 'Teams authenticated successfully.'
            else
              puts 'Teams authentication failed or was cancelled.'
            end
          rescue StandardError => e
            puts "Error: #{e.message}"
          end

          def status
            token_file = File.expand_path('~/.legionio/tokens/microsoft_teams.json')
            if File.exist?(token_file)
              puts 'Teams: authenticated (token file present)'
            else
              puts 'Teams: not authenticated'
            end
          end

          private

          def resolve_settings
            return {} unless defined?(Legion::Settings)

            Legion::Settings[:microsoft_teams]&.dig(:auth) || {}
          rescue StandardError
            {}
          end

          def store_token(result)
            cache = Helpers::TokenCache.new
            cache.store_delegated_token(result)
            cache.save_to_vault
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
