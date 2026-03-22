# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class AuthValidator < Legion::Extensions::Actors::Once
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def delay
            2.0
          end

          def enabled?
            defined?(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache)
          rescue StandardError
            false
          end

          def token_cache
            Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.instance
          end

          def manual
            log_info('AuthValidator starting')
            cache = token_cache
            log_debug("Token loaded: authenticated?=#{cache.authenticated?}")

            if cache.authenticated?
              token = cache.cached_delegated_token
              if token
                log_info('Teams delegated auth restored (token valid)')
              elsif cache.previously_authenticated? || auto_authenticate?
                log_info('Token loaded but expired, attempting browser re-auth')
                attempt_browser_reauth(cache)
              else
                log_debug('Token loaded but expired, no re-auth configured')
              end
            elsif cache.previously_authenticated?
              log_warn('Token file found but could not load, attempting re-authentication')
              attempt_browser_reauth(cache)
            elsif auto_authenticate?
              log_info('auto_authenticate enabled, opening browser for initial authentication...')
              attempt_browser_reauth(cache)
            else
              log_debug('No Teams delegated auth configured, skipping')
            end
            log_info('AuthValidator complete')
          rescue StandardError => e
            log_error("AuthValidator: #{e.message}")
          end

          private

          def attempt_browser_reauth(cache)
            settings = teams_auth_settings
            unless settings[:tenant_id] && settings[:client_id]
              log_warn("Cannot re-auth: tenant_id=#{settings[:tenant_id] ? 'present' : 'nil'}, client_id=#{settings[:client_id] ? 'present' : 'nil'}")
              return false
            end

            log_warn('Delegated token expired, opening browser for re-authentication...')

            scopes = settings.dig(:delegated, :scopes) ||
                     Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth::DEFAULT_SCOPES
            log_debug("Using scopes: #{scopes}")
            browser_auth = Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth.new(
              tenant_id: settings[:tenant_id],
              client_id: settings[:client_id],
              scopes:    scopes
            )

            result = browser_auth.authenticate
            if result[:error]
              log_error("Browser auth returned error: #{result[:error]} - #{result[:description]}")
              return false
            end

            body = result[:result]
            log_info("Browser auth succeeded, storing token (expires_in=#{body['expires_in']})")
            cache.store_delegated_token(
              access_token:  body['access_token'],
              refresh_token: body['refresh_token'],
              expires_in:    body['expires_in'],
              scopes:        scopes
            )
            cache.save_to_vault
            log_info('Teams delegated auth restored via browser')
            true
          rescue StandardError => e
            log_error("Browser re-auth failed: #{e.message}")
            false
          end

          def auto_authenticate?
            settings = teams_auth_settings
            result = settings.dig(:delegated, :auto_authenticate) == true
            log_debug("auto_authenticate? => #{result}")
            result
          end

          def teams_auth_settings
            settings = if defined?(Legion::Settings)
                         Legion::Settings.dig(:microsoft_teams, :auth) || {}
                       else
                         {}
                       end
            settings[:tenant_id] ||= ENV.fetch('AZURE_TENANT_ID', nil)
            settings[:client_id] ||= ENV.fetch('AZURE_CLIENT_ID', nil)
            settings
          end

          def log_info(msg)
            Legion::Logging.info("[Teams::AuthValidator] #{msg}") if defined?(Legion::Logging)
          end

          def log_warn(msg)
            Legion::Logging.warn("[Teams::AuthValidator] #{msg}") if defined?(Legion::Logging)
          end

          def log_debug(msg)
            Legion::Logging.debug("[Teams::AuthValidator] #{msg}") if defined?(Legion::Logging)
          end

          def log_error(msg)
            Legion::Logging.error("[Teams::AuthValidator] #{msg}") if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
