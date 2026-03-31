# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/browser_auth'
require 'legion/extensions/microsoft_teams/helpers/token_cache'

module Legion
  module Extensions
    module MicrosoftTeams
      module CLI
        class Auth
          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)

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
            tid = tenant_id || settings[:tenant_id] || ENV.fetch('AZURE_TENANT_ID', nil)
            cid = client_id || settings[:client_id] || ENV.fetch('AZURE_CLIENT_ID', nil)

            log.debug("Resolved tenant_id=#{tid ? 'present' : 'nil'}, client_id=#{cid ? 'present' : 'nil'}")

            unless tid && cid
              puts 'Error: tenant_id and client_id required (set in settings, env vars, or pass as args)'
              return
            end

            log.info('Starting Teams delegated auth login')
            browser_auth = Helpers::BrowserAuth.new(tenant_id: tid, client_id: cid, force_local_server: true)
            result = browser_auth.authenticate

            body = result&.dig(:result)
            if body&.dig('access_token')
              log.info('Authentication successful, storing token')
              store_token(body)
              puts 'Teams authenticated successfully.'
            else
              log.warn("Authentication result: #{result&.keys&.join(', ') || 'nil'}")
              puts 'Teams authentication failed or was cancelled.'
            end
          rescue StandardError => e
            log.error("Login failed: #{e.message}")
            puts "Error: #{e.message}"
          end

          def status
            token_file = File.expand_path('~/.legionio/tokens/microsoft_teams.json')
            if File.exist?(token_file)
              log.info("Token file found: #{token_file}")
              puts 'Teams: authenticated (token file present)'
            else
              log.info('No token file found')
              puts 'Teams: not authenticated'
            end
          end

          private

          def resolve_settings
            return {} unless defined?(Legion::Settings)

            Legion::Settings[:microsoft_teams]&.dig(:auth) || {}
          rescue StandardError => e
            log.debug("Auth: resolve_settings failed: #{e.message}")
            {}
          end

          def store_token(body)
            cache = Helpers::TokenCache.instance
            cache.store_delegated_token(
              access_token:  body['access_token'],
              refresh_token: body['refresh_token'],
              expires_in:    body['expires_in'],
              scopes:        body['scope']
            )
            cache.save_to_vault
            log.info('Token stored successfully')
          rescue StandardError => e
            log.error("Failed to store token: #{e.message}")
          end
        end
      end
    end
  end
end
