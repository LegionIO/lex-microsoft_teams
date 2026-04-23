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
          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
          include Legion::Crypt::Helper if defined?(Legion::Crypt::Helper)

          REFRESH_BUFFER = 60
          DEFAULT_LOCAL_DIR = File.join(Dir.home, '.legionio', 'tokens')
          DEFAULT_LOCAL_FILE = File.join(DEFAULT_LOCAL_DIR, 'microsoft_teams.json')

          @instance_mutex = Mutex.new

          def self.instance
            @instance_mutex.synchronize do
              @instance ||= begin
                cache = new
                cache.load_from_vault
                log.info('[Teams::TokenCache] Shared instance created and loaded')
                cache
              end
            end
          end

          def self.reset_instance!
            @instance_mutex.synchronize { @instance = nil }
          end

          def initialize
            @token_cache = nil
            @delegated_cache = nil
            @mutex = Mutex.new
            @app_token_warned = false
            log.debug('TokenCache initialized')
          end

          # --- Application token (client_credentials) ---

          def cached_app_token
            @mutex.synchronize do
              # Phase 8: Broker-managed Entra app token (short-circuits cache path)
              if defined?(Legion::Identity::Broker)
                token = Legion::Identity::Broker.token_for(:entra)
                return token if token
              end

              # Legacy: self-managed client_credentials + cache
              if @token_cache && !token_expired?(@token_cache)
                log.debug('Using cached app token')
                return @token_cache[:token]
              end

              result = refresh_app_token
              return result if result

              unless @app_token_warned
                log.warn('No app token available for Graph API calls')
                @app_token_warned = true
              end
              nil
            end
          end

          alias cached_graph_token cached_app_token

          def clear_token_cache!
            @mutex.synchronize do
              @token_cache = nil
              @app_token_warned = false
            end
            log.debug('App token cache cleared')
          end

          # --- Delegated token (user auth) ---

          def cached_delegated_token
            needs_refresh = @mutex.synchronize do
              unless @delegated_cache
                log.debug('No delegated token in cache')
                return nil
              end

              unless token_expired?(@delegated_cache)
                log.debug("Using cached delegated token (expires #{@delegated_cache[:expires_at]})")
                return @delegated_cache[:token]
              end

              true
            end

            return unless needs_refresh

            log.info('Delegated token expired, attempting refresh')
            refresh_delegated
          end

          def store_delegated_token(access_token:, refresh_token:, expires_in:, scopes:)
            expires_at = Time.now + expires_in.to_i
            @mutex.synchronize do
              @delegated_cache = {
                token:         access_token,
                refresh_token: refresh_token,
                expires_at:    expires_at,
                scopes:        scopes
              }
              @app_token_warned = false
            end
            log.info("Delegated token stored (expires_in=#{expires_in}s, expires_at=#{expires_at})")
          end

          def clear_delegated_token!
            @mutex.synchronize { @delegated_cache = nil }
            log.debug('Delegated token cache cleared')
          end

          def authenticated?
            result = @mutex.synchronize { !@delegated_cache.nil? }
            log.debug("authenticated? => #{result}")
            result
          end

          def previously_authenticated?
            path = local_token_path
            result = File.exist?(path)
            log.debug("previously_authenticated? => #{result} (#{path})")
            result
          end

          def load_from_vault
            if vault_available?
              log.info("Loading delegated token from Vault (#{vault_path})")
              data = vault_get(vault_path)
              if data && data[:access_token]
                @mutex.synchronize do
                  @delegated_cache = {
                    token:         data[:access_token],
                    refresh_token: data[:refresh_token],
                    expires_at:    Time.parse(data[:expires_at]),
                    scopes:        data[:scopes]
                  }
                end
                log.info('Delegated token loaded from Vault')
                true
              else
                log.warn('Vault had no delegated token, falling back to local')
                load_from_local
              end
            else
              log.debug('Vault not available, loading from local file')
              load_from_local
            end
          rescue StandardError => e
            log.error("Failed to load delegated token from Vault: #{e.message}")
            load_from_local
          end

          def save_to_vault
            save_to_local

            unless vault_available?
              log.debug('Vault not available, skipping Vault save')
              return false
            end

            data = @mutex.synchronize { @delegated_cache&.dup }
            unless data
              log.warn('No delegated token to save to Vault')
              return false
            end

            log.info("Saving delegated token to Vault (#{vault_path})")
            vault_write(vault_path, access_token:  data[:token],
                                    refresh_token: data[:refresh_token],
                                    expires_at:    data[:expires_at].utc.iso8601,
                                    scopes:        data[:scopes])
            log.info('Delegated token saved to Vault')
            true
          rescue StandardError => e
            log.error("Failed to save delegated token to Vault: #{e.message}")
            false
          end

          def load_from_local
            path = local_token_path
            unless File.exist?(path)
              log.debug("Local token file not found: #{path}")
              return false
            end

            log.info("Loading delegated token from local file: #{path}")
            raw = File.read(path)
            data = ::JSON.parse(raw)
            unless data['access_token'] && data['refresh_token']
              log.warn('Local token file missing access_token or refresh_token')
              return false
            end

            expires_at = Time.parse(data['expires_at'])
            @mutex.synchronize do
              @delegated_cache = {
                token:         data['access_token'],
                refresh_token: data['refresh_token'],
                expires_at:    expires_at,
                scopes:        data['scopes']
              }
            end
            log.info("Delegated token loaded from local file (expires_at=#{expires_at})")
            true
          rescue StandardError => e
            log.error("Failed to load delegated token from local file: #{e.message}")
            false
          end

          def save_to_local
            data = @mutex.synchronize { @delegated_cache&.dup }
            unless data
              log.warn('No delegated token to save locally')
              return false
            end

            path = local_token_path
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, ::JSON.pretty_generate(
                               'access_token'  => data[:token],
                               'refresh_token' => data[:refresh_token],
                               'expires_at'    => data[:expires_at].utc.iso8601,
                               'scopes'        => data[:scopes]
                             ))
            File.chmod(0o600, path)
            log.info("Delegated token saved to local file: #{path}")
            true
          rescue StandardError => e
            log.error("Failed to save delegated token to local file: #{e.message}")
            false
          end

          private

          def vault_available?
            return false unless defined?(Legion::Crypt)
            return false unless defined?(Legion::Settings)

            connected = Legion::Settings.dig(:crypt, :vault, :connected) == true
            log.debug("vault_available? => #{connected}")
            connected
          rescue StandardError => e
            log.debug("TokenCache: vault_available? check failed: #{e.message}")
            false
          end

          def token_expired?(cache_entry)
            return true unless cache_entry

            buffer = delegated_refresh_buffer
            expired = Time.now >= (cache_entry[:expires_at] - buffer)
            log.debug("token_expired? => #{expired} (expires_at=#{cache_entry[:expires_at]}, buffer=#{buffer}s)") if expired
            expired
          end

          def delegated_refresh_buffer
            settings = teams_auth_settings
            delegated = settings[:delegated]
            return REFRESH_BUFFER unless delegated.is_a?(Hash)

            delegated[:refresh_buffer] || REFRESH_BUFFER
          end

          def vault_path(_suffix = nil)
            settings = teams_auth_settings
            delegated = settings[:delegated]
            return delegated[:vault_path] if delegated.is_a?(Hash) && delegated[:vault_path]

            identity = if defined?(Legion::Identity::Process) && Legion::Identity::Process.resolved?
                         Legion::Identity::Process.canonical_name
                       else
                         ENV.fetch('USER', 'default').split('@').first
                       end
            "users/#{identity}/delegated_token"
          end

          def local_token_path
            settings = teams_auth_settings
            delegated = settings[:delegated]
            return DEFAULT_LOCAL_FILE unless delegated.is_a?(Hash)

            delegated[:local_token_path] || DEFAULT_LOCAL_FILE
          end

          def refresh_app_token
            result = acquire_fresh_token
            unless result
              unless @app_token_warned
                log.info('No client_secret configured, app token (client_credentials) unavailable')
                @app_token_warned = true
              end
              return nil
            end

            access_token = result.dig(:result, 'access_token')
            expires_in = result.dig(:result, 'expires_in') || 3600

            @token_cache = {
              token:      access_token,
              expires_at: Time.now + expires_in
            }

            log.info("App token refreshed (expires_in=#{expires_in}s)")
            access_token
          rescue StandardError => e
            log.error("TokenCache app refresh failed: #{e.message}")
            nil
          end

          def refresh_delegated
            unless @delegated_cache&.dig(:refresh_token)
              log.warn('No refresh token available for delegated refresh')
              return nil
            end

            settings = teams_auth_settings
            unless settings[:tenant_id] && settings[:client_id]
              log.warn('Missing tenant_id or client_id for delegated refresh')
              return nil
            end

            log.info('Refreshing delegated token via refresh_token grant')
            auth = Object.new.extend(Legion::Extensions::MicrosoftTeams::Runners::Auth)
            result = auth.refresh_delegated_token(
              tenant_id:     settings[:tenant_id],
              client_id:     settings[:client_id],
              refresh_token: @delegated_cache[:refresh_token],
              scope:         @delegated_cache[:scopes]
            )

            body = result[:result]
            unless body&.dig('access_token')
              log.warn("Delegated token refresh failed: #{result[:error]}")
              return handle_refresh_failure(result)
            end

            expires_in = (body['expires_in'] || 3600).to_i
            @delegated_cache = {
              token:         body['access_token'],
              refresh_token: body['refresh_token'] || @delegated_cache[:refresh_token],
              expires_at:    Time.now + expires_in,
              scopes:        @delegated_cache[:scopes]
            }

            log.info("Delegated token refreshed (expires_in=#{expires_in}s)")
            save_to_vault
            @delegated_cache[:token]
          rescue StandardError => e
            log.error("TokenCache delegated refresh failed: #{e.message}")
            nil
          end

          def handle_refresh_failure(result)
            if result[:error] == 'invalid_grant'
              log.warn('Refresh token invalid (invalid_grant), clearing delegated cache')
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
            unless settings[:tenant_id] && settings[:client_id] && settings[:client_secret]
              log.debug('Missing credentials for app token acquisition') unless @app_token_warned
              return nil
            end

            log.debug('Acquiring fresh app token via client_credentials')
            auth = Object.new.extend(Legion::Extensions::MicrosoftTeams::Runners::Auth)
            auth.acquire_token(
              tenant_id:     settings[:tenant_id],
              client_id:     settings[:client_id],
              client_secret: settings[:client_secret]
            )
          end

          def teams_auth_settings
            ms = settings
            ms = Legion::Settings[:microsoft_teams] if defined?(Legion::Settings) && (ms.nil? || ms.empty?)
            ms ||= {}
            auth = ms[:auth].is_a?(Hash) ? ms[:auth].dup : {}
            auth[:tenant_id] ||= ms[:tenant_id]
            auth[:client_id] ||= ms[:client_id]
            auth[:client_secret] ||= ms[:client_secret]
            auth[:tenant_id] ||= ENV.fetch('AZURE_TENANT_ID', nil)
            auth[:client_id] ||= ENV.fetch('AZURE_CLIENT_ID', nil)
            auth[:client_secret] ||= ENV.fetch('AZURE_CLIENT_SECRET', nil)
            auth
          end
        end
      end
    end
  end
end
