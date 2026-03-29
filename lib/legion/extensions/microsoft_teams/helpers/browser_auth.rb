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
          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)

          DEFAULT_SCOPES = [
            'offline_access', 'openid', 'profile', 'email',
            'User.Read', 'People.Read', 'Presence.Read', 'Presence.Read.All',
            'Chat.Read', 'Chat.ReadBasic', 'ChatMember.Read', 'ChatMessage.Read',
            'Channel.ReadBasic.All', 'ChannelMember.Read.All', 'ChannelMessage.Read.All',
            'Team.ReadBasic.All', 'Group-Conversation.Read.All',
            'OnlineMeetings.Read', 'OnlineMeetingTranscript.Read.All',
            'OnlineMeetingRecording.Read.All', 'OnlineMeetingArtifact.Read.All',
            'OnlineMeetingAiInsight.Read.All', 'CallAiInsights.Read.All',
            'CallEvents.Read', 'CallRecordings.Read.All', 'CallTranscripts.Read.All',
            'TeamsActivity.Read', 'TeamsActivity.Send'
          ].join(' ').freeze

          attr_reader :tenant_id, :client_id, :scopes

          def initialize(tenant_id:, client_id:, scopes: DEFAULT_SCOPES, auth: nil, force_local_server: false, **)
            @tenant_id = tenant_id
            @client_id = client_id
            @scopes    = scopes
            @auth      = auth || Object.new.extend(Runners::Auth)
            @force_local_server = force_local_server
            log.debug("BrowserAuth initialized (tenant=#{tenant_id}, client=#{client_id}, force_local=#{force_local_server})")
          end

          def authenticate
            if gui_available?
              log.info('GUI available, using browser auth')
              authenticate_browser
            else
              log.info('No GUI detected, using device code flow')
              authenticate_device_code
            end
          end

          def api_hook_available?
            if @force_local_server
              log.debug('api_hook_available? => false (force_local_server)')
              return false
            end

            api_defined = defined?(Legion::API)
            events_defined = defined?(Legion::Events)
            hooks_defined = defined?(Legion::Extensions::Hooks::Base)
            route_ok = api_defined && events_defined && hooks_defined && hook_route_registered?

            log.debug("api_hook_available? => #{!route_ok.nil?} " \
                      "(API=#{!api_defined.nil?}, Events=#{!events_defined.nil?}, Hooks=#{!hooks_defined.nil?}, route=#{route_ok})")
            !!route_ok
          end

          def hook_redirect_uri
            port = if defined?(Legion::Settings)
                     Legion::Settings.dig(:api, :port) || 4567
                   else
                     4567
                   end
            "http://127.0.0.1:#{port}/api/extensions/microsoft_teams/hooks/auth/handle"
          end

          def generate_pkce
            verifier  = SecureRandom.urlsafe_base64(32)
            challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
            log.debug('PKCE challenge generated')
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
            unless cmd
              log.warn('No browser command found for this OS')
              return false
            end

            log.debug("Opening browser with: #{cmd}")
            system(cmd, url)
          end

          private

          def log
            return Legion::Logging if defined?(Legion::Logging)

            @log ||= Object.new.tap do |nl|
              %i[debug info warn error fatal].each { |m| nl.define_singleton_method(m) { |*| nil } }
            end
          end

          def host_os
            RbConfig::CONFIG['host_os']
          end

          def hook_route_registered?
            return false unless defined?(Legion::API)

            log.debug("Probing hook route at http://127.0.0.1:#{api_port}/api/extensions/microsoft_teams/hooks/auth/handle")
            conn = Faraday.new(url: "http://127.0.0.1:#{api_port}")
            resp = conn.head('/api/extensions/microsoft_teams/hooks/auth/handle')
            registered = resp.status != 404
            log.debug("Hook route probe returned #{resp.status} (registered=#{registered})")
            registered
          rescue StandardError => e
            log.debug("Hook route probe failed: #{e.message}")
            false
          end

          def api_port
            if defined?(Legion::Settings)
              Legion::Settings.dig(:api, :port) || 4567
            else
              4567
            end
          end

          def authenticate_browser
            verifier, challenge = generate_pkce
            state = SecureRandom.hex(32)

            if api_hook_available?
              log.info('Using API hook for OAuth callback')
              authenticate_via_hook(verifier: verifier, challenge: challenge, state: state)
            else
              log.info('Using local callback server for OAuth callback')
              authenticate_via_server(verifier: verifier, challenge: challenge, state: state)
            end
          end

          def authenticate_via_hook(verifier:, challenge:, state:)
            callback_uri = hook_redirect_uri
            log.debug("Hook callback URI: #{callback_uri}")
            result_holder = { result: nil }
            mutex = Mutex.new
            cv = ConditionVariable.new

            listener = Legion::Events.once('microsoft_teams.oauth.callback') do |event|
              log.debug('OAuth callback event received via Legion::Events')
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

            log.info('Opening browser for authentication (using API hook)...')
            unless open_browser(url)
              Legion::Events.off('microsoft_teams.oauth.callback', listener)
              log.warn('Could not open browser. Falling back to device code flow.')
              return authenticate_device_code
            end

            log.debug('Waiting for OAuth callback (timeout=120s)...')
            mutex.synchronize { cv.wait(mutex, 120) unless result_holder[:result] }
            result = result_holder[:result]

            unless result && result[:code]
              log.error('OAuth callback timed out or missing code')
              return { error: 'timeout', description: 'No callback received within timeout' }
            end

            unless result[:state] == state
              log.error('OAuth state mismatch (possible CSRF)')
              return { error: 'state_mismatch', description: 'CSRF state parameter mismatch' }
            end

            log.info('Exchanging authorization code for tokens (via hook)')
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
            log.info("Local callback server started on #{callback_uri}")

            url = @auth.authorize_url(
              tenant_id: tenant_id, client_id: client_id,
              redirect_uri: callback_uri, scope: scopes,
              state: state, code_challenge: challenge
            )

            log.info("Opening browser for authentication (callback: #{callback_uri})...")
            unless open_browser(url)
              log.warn('Could not open browser. Falling back to device code flow.')
              return authenticate_device_code
            end

            log.debug('Waiting for OAuth callback on local server (timeout=120s)...')
            result = server.wait_for_callback(timeout: 120)

            unless result && result[:code]
              log.error('OAuth callback timed out or missing code')
              return { error: 'timeout', description: 'No callback received within timeout' }
            end

            unless result[:state] == state
              log.error('OAuth state mismatch (possible CSRF)')
              return { error: 'state_mismatch', description: 'CSRF state parameter mismatch' }
            end

            log.info('Exchanging authorization code for tokens (via local server)')
            @auth.exchange_code(
              tenant_id: tenant_id, client_id: client_id,
              code: result[:code], redirect_uri: callback_uri,
              code_verifier: verifier, scope: scopes
            )
          ensure
            server&.shutdown
            log.debug('Local callback server shut down')
          end

          def authenticate_device_code
            log.info('Starting device code flow')
            dc = @auth.request_device_code(
              tenant_id: tenant_id,
              client_id: client_id,
              scope:     scopes
            )
            if dc[:error]
              log.error("Device code request failed: #{dc[:error]} - #{dc[:description]}")
              return { error: dc[:error], description: dc[:description] }
            end

            body = dc[:result]

            log.info("Go to:  #{body['verification_uri']}")
            log.info("Code:   #{body['user_code']}")

            open_browser(body['verification_uri']) if gui_available?

            log.debug('Polling for device code authorization...')
            @auth.poll_device_code(
              tenant_id:   tenant_id,
              client_id:   client_id,
              device_code: body['device_code']
            )
          end
        end
      end
    end
  end
end
