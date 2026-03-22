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
            tid = tenant_id || settings[:tenant_id] || ENV.fetch('AZURE_TENANT_ID', nil)
            cid = client_id || settings[:client_id] || ENV.fetch('AZURE_CLIENT_ID', nil)

            log_debug("Resolved tenant_id=#{tid ? 'present' : 'nil'}, client_id=#{cid ? 'present' : 'nil'}")

            unless tid && cid
              puts 'Error: tenant_id and client_id required (set in settings, env vars, or pass as args)'
              return
            end

            log_info('Starting Teams delegated auth login')
            browser_auth = Helpers::BrowserAuth.new(tenant_id: tid, client_id: cid, force_local_server: true)
            result = browser_auth.authenticate

            if result&.dig(:access_token)
              log_info('Authentication successful, storing token')
              store_token(result)
              puts 'Teams authenticated successfully.'
            else
              log_warn("Authentication result: #{result&.keys&.join(', ') || 'nil'}")
              puts 'Teams authentication failed or was cancelled.'
            end
          rescue StandardError => e
            log_error("Login failed: #{e.message}")
            puts "Error: #{e.message}"
          end

          def status
            token_file = File.expand_path('~/.legionio/tokens/microsoft_teams.json')
            if File.exist?(token_file)
              log_info("Token file found: #{token_file}")
              puts 'Teams: authenticated (token file present)'
            else
              log_info('No token file found')
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
            log_info('Token stored successfully')
          rescue StandardError => e
            log_error("Failed to store token: #{e.message}")
          end

          def log_debug(msg)
            if defined?(Legion::Logging)
              Legion::Logging.debug("[Teams::CLI::Auth] #{msg}")
            else
              $stdout.puts("[DEBUG] [Teams::CLI::Auth] #{msg}")
            end
          end

          def log_info(msg)
            if defined?(Legion::Logging)
              Legion::Logging.info("[Teams::CLI::Auth] #{msg}")
            else
              $stdout.puts("[INFO] [Teams::CLI::Auth] #{msg}")
            end
          end

          def log_warn(msg)
            if defined?(Legion::Logging)
              Legion::Logging.warn("[Teams::CLI::Auth] #{msg}")
            else
              $stdout.puts("[WARN] [Teams::CLI::Auth] #{msg}")
            end
          end

          def log_error(msg)
            if defined?(Legion::Logging)
              Legion::Logging.error("[Teams::CLI::Auth] #{msg}")
            else
              $stdout.puts("[ERROR] [Teams::CLI::Auth] #{msg}")
            end
          end
        end
      end
    end
  end
end
