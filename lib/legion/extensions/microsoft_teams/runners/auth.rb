# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Auth
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def acquire_token(tenant_id:, client_id:, client_secret:, scope: 'https://graph.microsoft.com/.default', **)
            response = oauth_connection(tenant_id: tenant_id).post('oauth2/v2.0/token', {
                                                                     grant_type:    'client_credentials',
                                                                     client_id:     client_id,
                                                                     client_secret: client_secret,
                                                                     scope:         scope
                                                                   })
            { result: response.body }
          end

          def acquire_bot_token(client_id:, client_secret:,
                                scope: 'https://api.botframework.com/.default', **)
            response = oauth_connection(tenant_id: 'botframework.com').post('oauth2/v2.0/token', {
                                                                              grant_type:    'client_credentials',
                                                                              client_id:     client_id,
                                                                              client_secret: client_secret,
                                                                              scope:         scope
                                                                            })
            { result: response.body }
          end

          def request_device_code(tenant_id:, client_id:,
                                  scope: 'OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access', **)
            response = oauth_connection(tenant_id: tenant_id).post('oauth2/v2.0/devicecode', {
                                                                     client_id: client_id,
                                                                     scope:     scope
                                                                   })
            { result: response.body }
          end

          def poll_device_code(tenant_id:, client_id:, device_code:, interval: 5, timeout: 300, **)
            conn = oauth_connection(tenant_id: tenant_id)
            deadline = Time.now + timeout
            current_interval = interval

            loop do
              response = conn.post('oauth2/v2.0/token', {
                                     grant_type:  'urn:ietf:params:oauth:grant-type:device_code',
                                     client_id:   client_id,
                                     device_code: device_code
                                   })
              body = response.body

              return { result: body } if body['access_token']

              case body['error']
              when 'authorization_pending'
                return { error: 'timeout', description: "Device code flow timed out after #{timeout}s" } if Time.now > deadline

                sleep(current_interval)
              when 'slow_down'
                current_interval += 5
                sleep(current_interval)
              else
                return { error: body['error'], description: body['error_description'] }
              end
            end
          end

          def authorize_url(tenant_id:, client_id:, redirect_uri:, scope:, state:,
                            code_challenge:, code_challenge_method: 'S256', **)
            require 'uri'
            params = URI.encode_www_form(
              client_id:             client_id,
              response_type:         'code',
              redirect_uri:          redirect_uri,
              scope:                 scope,
              state:                 state,
              code_challenge:        code_challenge,
              code_challenge_method: code_challenge_method
            )
            "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/authorize?#{params}"
          end

          def exchange_code(tenant_id:, client_id:, code:, redirect_uri:, code_verifier:,
                            scope: 'OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access', **)
            response = oauth_connection(tenant_id: tenant_id).post('oauth2/v2.0/token', {
                                                                     grant_type:    'authorization_code',
                                                                     client_id:     client_id,
                                                                     code:          code,
                                                                     redirect_uri:  redirect_uri,
                                                                     code_verifier: code_verifier,
                                                                     scope:         scope
                                                                   })
            { result: response.body }
          end

          def refresh_delegated_token(tenant_id:, client_id:, refresh_token:,
                                      scope: 'OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access', **)
            response = oauth_connection(tenant_id: tenant_id).post('oauth2/v2.0/token', {
                                                                     grant_type:    'refresh_token',
                                                                     client_id:     client_id,
                                                                     refresh_token: refresh_token,
                                                                     scope:         scope
                                                                   })
            { result: response.body }
          end

          def auth_callback(code: nil, state: nil, **)
            unless code && state
              return {
                result:   { error: 'missing_params' },
                response: { status: 400, content_type: 'text/html',
                            body: '<html><body><h2>Missing code or state parameter</h2></body></html>' }
              }
            end

            Legion::Events.emit('microsoft_teams.oauth.callback', code: code, state: state) if defined?(Legion::Events)

            {
              result:   { authenticated: true, code: code, state: state },
              response: { status: 200, content_type: 'text/html',
                          body: callback_success_html }
            }
          end
          alias handle auth_callback

          private

          def callback_success_html
            <<~HTML
              <html><body style="font-family:sans-serif;text-align:center;padding:40px;">
              <h2>Authentication complete</h2>
              <p>You can close this window.</p>
              </body></html>
            HTML
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
