# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/runners/auth'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        class TokenCache
          REFRESH_BUFFER = 60

          def initialize
            @token_cache = nil
            @mutex = Mutex.new
          end

          def cached_graph_token
            @mutex.synchronize do
              return @token_cache[:token] if @token_cache && !token_expired?

              refresh_token
            end
          end

          def clear_token_cache!
            @mutex.synchronize { @token_cache = nil }
          end

          private

          def token_expired?
            return true unless @token_cache

            Time.now >= (@token_cache[:expires_at] - REFRESH_BUFFER)
          end

          def refresh_token
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
            log_error("TokenCache refresh failed: #{e.message}")
            nil
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
