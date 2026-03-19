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
            @token_cache ||= Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.new
          end

          def manual
            loaded = token_cache.load_from_vault

            if loaded
              token = token_cache.cached_delegated_token
              if token
                log_info('Teams delegated auth restored')
              elsif token_cache.previously_authenticated?
                attempt_browser_reauth(token_cache)
              end
            elsif token_cache.previously_authenticated?
              log_warn('Token file found but could not load, attempting re-authentication')
              attempt_browser_reauth(token_cache)
            else
              log_debug('No Teams delegated auth configured, skipping')
            end
          rescue StandardError => e
            log_error("AuthValidator: #{e.message}")
          end

          private

          def attempt_browser_reauth(cache)
            settings = teams_auth_settings
            return false unless settings[:tenant_id] && settings[:client_id]

            log_warn('Delegated token expired, opening browser for re-authentication...')

            scopes = settings.dig(:delegated, :scopes) ||
                     Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth::DEFAULT_SCOPES
            browser_auth = Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth.new(
              tenant_id: settings[:tenant_id],
              client_id: settings[:client_id],
              scopes:    scopes
            )

            result = browser_auth.authenticate
            return false if result[:error]

            body = result[:result]
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

          def teams_auth_settings
            return {} unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :auth) || {}
          end

          def log_info(msg)
            Legion::Logging.info(msg) if defined?(Legion::Logging)
          end

          def log_warn(msg)
            Legion::Logging.warn(msg) if defined?(Legion::Logging)
          end

          def log_debug(msg)
            Legion::Logging.debug(msg) if defined?(Legion::Logging)
          end

          def log_error(msg)
            Legion::Logging.error(msg) if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
