# frozen_string_literal: true

require 'securerandom'
require 'digest'
require 'base64'
require 'rbconfig'

require 'legion/extensions/microsoft_teams/runners/auth'
require 'legion/extensions/microsoft_teams/helpers/callback_server'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        class BrowserAuth
          DEFAULT_SCOPES = 'OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access'

          attr_reader :tenant_id, :client_id, :scopes

          def initialize(tenant_id:, client_id:, scopes: DEFAULT_SCOPES, auth: nil, **)
            @tenant_id = tenant_id
            @client_id = client_id
            @scopes    = scopes
            @auth      = auth || Object.new.extend(Runners::Auth)
          end

          def authenticate
            if gui_available?
              authenticate_browser
            else
              authenticate_device_code
            end
          end

          def api_hook_available?
            !!(defined?(Legion::API) && defined?(Legion::Events))
          end

          def hook_redirect_uri
            port = if defined?(Legion::Settings)
                     Legion::Settings.dig(:api, :port) || 4567
                   else
                     4567
                   end
            "http://127.0.0.1:#{port}/api/hooks/lex/microsoft_teams/auth/callback"
          end

          def generate_pkce
            verifier  = SecureRandom.urlsafe_base64(32)
            challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
            [verifier, challenge]
          end

          def gui_available?
            os = host_os
            return true if os =~ /darwin|mswin|mingw/

            !ENV['DISPLAY'].nil? || !ENV['WAYLAND_DISPLAY'].nil?
          end

          def open_browser(url)
            cmd = case host_os
                  when /darwin/       then 'open'
                  when /linux/        then 'xdg-open'
                  when /mswin|mingw/  then 'start'
                  end
            return false unless cmd

            system(cmd, url)
          end

          private

          def host_os
            RbConfig::CONFIG['host_os']
          end

          def authenticate_browser
            verifier, challenge = generate_pkce
            state = SecureRandom.hex(32)

            if api_hook_available?
              authenticate_via_hook(verifier: verifier, challenge: challenge, state: state)
            else
              authenticate_via_server(verifier: verifier, challenge: challenge, state: state)
            end
          end

          def authenticate_via_hook(verifier:, challenge:, state:)
            callback_uri = hook_redirect_uri
            result_holder = { result: nil }
            mutex = Mutex.new
            cv = ConditionVariable.new

            listener = Legion::Events.once('microsoft_teams.oauth.callback') do |event|
              mutex.synchronize do
                result_holder[:result] = event
                cv.broadcast
              end
            end

            url = @auth.authorize_url(
              tenant_id: tenant_id, client_id: client_id,
              redirect_uri: callback_uri, scope: scopes,
              state: state, code_challenge: challenge
            )

            log_info('Opening browser for authentication (using API hook)...')
            unless open_browser(url)
              Legion::Events.off('microsoft_teams.oauth.callback', listener)
              log_info('Could not open browser. Falling back to device code flow.')
              return authenticate_device_code
            end

            mutex.synchronize { cv.wait(mutex, 120) unless result_holder[:result] }
            result = result_holder[:result]

            return { error: 'timeout', description: 'No callback received within timeout' } unless result && result[:code]

            return { error: 'state_mismatch', description: 'CSRF state parameter mismatch' } unless result[:state] == state

            @auth.exchange_code(
              tenant_id: tenant_id, client_id: client_id,
              code: result[:code], redirect_uri: callback_uri,
              code_verifier: verifier, scope: scopes
            )
          end

          def authenticate_via_server(verifier:, challenge:, state:)
            server = CallbackServer.new
            server.start
            callback_uri = server.redirect_uri

            url = @auth.authorize_url(
              tenant_id: tenant_id, client_id: client_id,
              redirect_uri: callback_uri, scope: scopes,
              state: state, code_challenge: challenge
            )

            log_info('Opening browser for authentication...')
            unless open_browser(url)
              log_info('Could not open browser. Falling back to device code flow.')
              return authenticate_device_code
            end

            result = server.wait_for_callback(timeout: 120)

            return { error: 'timeout', description: 'No callback received within timeout' } unless result && result[:code]

            return { error: 'state_mismatch', description: 'CSRF state parameter mismatch' } unless result[:state] == state

            @auth.exchange_code(
              tenant_id: tenant_id, client_id: client_id,
              code: result[:code], redirect_uri: callback_uri,
              code_verifier: verifier, scope: scopes
            )
          ensure
            server&.shutdown
          end

          def authenticate_device_code
            dc = @auth.request_device_code(
              tenant_id: tenant_id,
              client_id: client_id,
              scope:     scopes
            )
            return { error: dc[:error], description: dc[:description] } if dc[:error]

            body = dc[:result]

            log_info("Go to:  #{body['verification_uri']}")
            log_info("Code:   #{body['user_code']}")

            open_browser(body['verification_uri']) if gui_available?

            @auth.poll_device_code(
              tenant_id:   tenant_id,
              client_id:   client_id,
              device_code: body['device_code']
            )
          end

          def log_info(msg)
            if defined?(Legion::Logging)
              Legion::Logging.info(msg)
            else
              $stdout.puts(msg)
            end
          end
        end
      end
    end
  end
end
