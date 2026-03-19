# frozen_string_literal: true

require 'time'
require 'json'
require 'fileutils'
require 'legion/extensions/microsoft_teams/runners/auth'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        class TokenCache
          REFRESH_BUFFER = 60
          DEFAULT_VAULT_PATH = 'legionio/microsoft_teams/delegated_token'
          DEFAULT_LOCAL_DIR = File.join(Dir.home, '.legionio', 'tokens')
          DEFAULT_LOCAL_FILE = File.join(DEFAULT_LOCAL_DIR, 'microsoft_teams.json')

          def initialize
            @token_cache = nil
            @delegated_cache = nil
            @mutex = Mutex.new
          end

          # --- Application token (client_credentials) ---

          def cached_graph_token
            @mutex.synchronize do
              return @token_cache[:token] if @token_cache && !token_expired?(@token_cache)

              refresh_app_token
            end
          end

          def clear_token_cache!
            @mutex.synchronize { @token_cache = nil }
          end

          # --- Delegated token (user auth) ---

          def cached_delegated_token
            @mutex.synchronize do
              return nil unless @delegated_cache

              return @delegated_cache[:token] unless token_expired?(@delegated_cache)

              refresh_delegated
            end
          end

          def store_delegated_token(access_token:, refresh_token:, expires_in:, scopes:)
            @mutex.synchronize do
              @delegated_cache = {
                token:         access_token,
                refresh_token: refresh_token,
                expires_at:    Time.now + expires_in.to_i,
                scopes:        scopes
              }
            end
          end

          def clear_delegated_token!
            @mutex.synchronize { @delegated_cache = nil }
          end

          def load_from_vault
            return load_from_local unless defined?(Legion::Crypt)

            data = Legion::Crypt.get(vault_path)
            return load_from_local unless data && data[:access_token]

            @mutex.synchronize do
              @delegated_cache = {
                token:         data[:access_token],
                refresh_token: data[:refresh_token],
                expires_at:    Time.parse(data[:expires_at]),
                scopes:        data[:scopes]
              }
            end
            true
          rescue StandardError => e
            log_error("Failed to load delegated token from Vault: #{e.message}")
            load_from_local
          end

          def save_to_vault
            save_to_local

            return false unless defined?(Legion::Crypt)

            data = @mutex.synchronize { @delegated_cache&.dup }
            return false unless data

            Legion::Crypt.write(vault_path,
                                access_token:  data[:token],
                                refresh_token: data[:refresh_token],
                                expires_at:    data[:expires_at].utc.iso8601,
                                scopes:        data[:scopes])
            true
          rescue StandardError => e
            log_error("Failed to save delegated token to Vault: #{e.message}")
            false
          end

          def load_from_local
            path = local_token_path
            return false unless File.exist?(path)

            raw = File.read(path)
            data = ::JSON.parse(raw)
            return false unless data['access_token'] && data['refresh_token']

            @mutex.synchronize do
              @delegated_cache = {
                token:         data['access_token'],
                refresh_token: data['refresh_token'],
                expires_at:    Time.parse(data['expires_at']),
                scopes:        data['scopes']
              }
            end
            true
          rescue StandardError => e
            log_error("Failed to load delegated token from local file: #{e.message}")
            false
          end

          def save_to_local
            data = @mutex.synchronize { @delegated_cache&.dup }
            return false unless data

            path = local_token_path
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, ::JSON.pretty_generate(
                               'access_token'  => data[:token],
                               'refresh_token' => data[:refresh_token],
                               'expires_at'    => data[:expires_at].utc.iso8601,
                               'scopes'        => data[:scopes]
                             ))
            File.chmod(0o600, path)
            true
          rescue StandardError => e
            log_error("Failed to save delegated token to local file: #{e.message}")
            false
          end

          private

          def token_expired?(cache_entry)
            return true unless cache_entry

            buffer = delegated_refresh_buffer
            Time.now >= (cache_entry[:expires_at] - buffer)
          end

          def delegated_refresh_buffer
            settings = teams_auth_settings
            delegated = settings[:delegated]
            return REFRESH_BUFFER unless delegated.is_a?(Hash)

            delegated[:refresh_buffer] || REFRESH_BUFFER
          end

          def vault_path
            settings = teams_auth_settings
            delegated = settings[:delegated]
            return DEFAULT_VAULT_PATH unless delegated.is_a?(Hash)

            delegated[:vault_path] || DEFAULT_VAULT_PATH
          end

          def local_token_path
            settings = teams_auth_settings
            delegated = settings[:delegated]
            return DEFAULT_LOCAL_FILE unless delegated.is_a?(Hash)

            delegated[:local_token_path] || DEFAULT_LOCAL_FILE
          end

          def refresh_app_token
            result = acquire_fresh_token
            return nil unless result

            access_token = result.dig(:result, 'access_token')
            expires_in = result.dig(:result, 'expires_in') || 3600

            @token_cache = {
              token:      access_token,
              expires_at: Time.now + expires_in
            }

            access_token
          rescue StandardError => e
            log_error("TokenCache app refresh failed: #{e.message}")
            nil
          end

          def refresh_delegated
            return nil unless @delegated_cache&.dig(:refresh_token)

            settings = teams_auth_settings
            return nil unless settings[:tenant_id] && settings[:client_id]

            auth = Object.new.extend(Legion::Extensions::MicrosoftTeams::Runners::Auth)
            result = auth.refresh_delegated_token(
              tenant_id:     settings[:tenant_id],
              client_id:     settings[:client_id],
              refresh_token: @delegated_cache[:refresh_token],
              scope:         @delegated_cache[:scopes]
            )

            body = result[:result]
            return handle_refresh_failure(result) unless body&.dig('access_token')

            @delegated_cache = {
              token:         body['access_token'],
              refresh_token: body['refresh_token'] || @delegated_cache[:refresh_token],
              expires_at:    Time.now + (body['expires_in'] || 3600).to_i,
              scopes:        @delegated_cache[:scopes]
            }

            save_to_vault
            @delegated_cache[:token]
          rescue StandardError => e
            log_error("TokenCache delegated refresh failed: #{e.message}")
            nil
          end

          def handle_refresh_failure(result)
            if result[:error] == 'invalid_grant'
              @delegated_cache = nil
              emit_expired_event
            end
            nil
          end

          def emit_expired_event
            Legion::Events.emit('microsoft_teams.auth.expired') if defined?(Legion::Events)
          end

          def acquire_fresh_token
            settings = teams_auth_settings
            return nil unless settings[:tenant_id] && settings[:client_id] && settings[:client_secret]

            auth = Object.new.extend(Legion::Extensions::MicrosoftTeams::Runners::Auth)
            auth.acquire_token(
              tenant_id:     settings[:tenant_id],
              client_id:     settings[:client_id],
              client_secret: settings[:client_secret]
            )
          end

          def teams_auth_settings
            return {} unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :auth) || {}
          end

          def log_error(msg)
            Legion::Logging.error(msg) if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
