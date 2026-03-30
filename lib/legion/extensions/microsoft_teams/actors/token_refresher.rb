# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class TokenRefresher < Legion::Extensions::Actors::Every
          DEFAULT_REFRESH_INTERVAL = 900

          def runner_class    = Legion::Extensions::MicrosoftTeams::Helpers::TokenCache
          def runner_function = 'cached_delegated_token'
          def run_now?        = false
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def time
            settings = teams_auth_settings
            delegated = settings[:delegated]
            return DEFAULT_REFRESH_INTERVAL unless delegated.is_a?(Hash)

            delegated[:refresh_interval] || DEFAULT_REFRESH_INTERVAL
          end

          def enabled?
            defined?(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache)
          rescue StandardError => e
            log.debug("TokenRefresher#enabled?: #{e.message}")
            false
          end

          def token_cache
            Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.instance
          end

          def manual
            log.debug('TokenRefresher tick')
            unless token_cache.authenticated?
              log.debug('No active delegated token, skipping refresh')
              return
            end

            log.info('Checking delegated token freshness')
            token = token_cache.cached_delegated_token
            if token
              log.info('Delegated token still valid, persisting')
              token_cache.save_to_vault
            elsif token_cache.previously_authenticated?
              log.warn('Delegated token expired, attempting browser re-auth')
              attempt_browser_reauth(token_cache)
            else
              log.warn('Delegated token expired, no previous auth to restore')
            end
          rescue StandardError => e
            log.error("TokenRefresher: #{e.message}")
          end

          private

          def attempt_browser_reauth(cache)
            settings = teams_auth_settings
            unless settings[:tenant_id] && settings[:client_id]
              log.warn("Cannot re-auth: tenant_id=#{settings[:tenant_id] ? 'present' : 'nil'}, client_id=#{settings[:client_id] ? 'present' : 'nil'}")
              return false
            end

            log.warn('Delegated token expired, opening browser for re-authentication...')

            scopes = settings.dig(:delegated, :scopes) ||
                     Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth::DEFAULT_SCOPES
            log.debug("Using scopes: #{scopes}")
            browser_auth = Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth.new(
              tenant_id: settings[:tenant_id],
              client_id: settings[:client_id],
              scopes:    scopes
            )

            result = browser_auth.authenticate
            if result[:error]
              log.error("Browser auth returned error: #{result[:error]} - #{result[:description]}")
              return false
            end

            body = result[:result]
            log.info("Browser auth succeeded, storing token (expires_in=#{body['expires_in']})")
            cache.store_delegated_token(
              access_token:  body['access_token'],
              refresh_token: body['refresh_token'],
              expires_in:    body['expires_in'],
              scopes:        scopes
            )
            cache.save_to_vault
            log.info('Teams delegated auth restored via browser')
            true
          rescue StandardError => e
            log.error("Browser re-auth failed: #{e.message}")
            false
          end

          def teams_auth_settings
            settings = if defined?(Legion::Settings)
                         ms = Legion::Settings[:microsoft_teams]
                         auth = if ms && ms[:auth].is_a?(Hash)
                                  ms[:auth].dup
                                else
                                  {}
                                end
                         auth[:tenant_id] ||= ms[:tenant_id] if ms
                         auth[:client_id] ||= ms[:client_id] if ms
                         auth
                       else
                         {}
                       end
            settings[:tenant_id] ||= ENV.fetch('AZURE_TENANT_ID', nil)
            settings[:client_id] ||= ENV.fetch('AZURE_CLIENT_ID', nil)
            settings
          end
        end
      end
    end
  end
end
