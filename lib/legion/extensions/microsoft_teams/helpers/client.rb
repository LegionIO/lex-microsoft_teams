# frozen_string_literal: true

require 'faraday'
require 'legion/extensions/microsoft_teams/faraday/retry_after'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        module Client
          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)

          def graph_connection(token: nil, api_url: 'https://graph.microsoft.com/v1.0', **_opts)
            token ||= entra_delegated_token
            ::Faraday.new(url: api_url) do |conn|
              conn.request :json
              conn.use Legion::Extensions::MicrosoftTeams::Faraday::RetryAfter, **retry_after_options
              conn.response :json, content_type: /\bjson$/
              conn.headers['Authorization'] = "Bearer #{token}" if token
              conn.headers['Content-Type'] = 'application/json'
            end
          end

          def bot_connection(token: nil, service_url: 'https://smba.trafficmanager.net/teams/', **_opts)
            ::Faraday.new(url: service_url) do |conn|
              conn.request :json
              conn.use Legion::Extensions::MicrosoftTeams::Faraday::RetryAfter, **retry_after_options
              conn.response :json, content_type: /\bjson$/
              conn.headers['Authorization'] = "Bearer #{token}" if token
              conn.headers['Content-Type'] = 'application/json'
            end
          end

          def user_path(user_id = 'me')
            user_id == 'me' ? 'me' : "users/#{user_id}"
          end

          def oauth_connection(tenant_id: 'common', **_opts)
            ::Faraday.new(url: "https://login.microsoftonline.com/#{tenant_id}") do |conn|
              conn.request :url_encoded
              conn.response :json, content_type: /\bjson$/
            end
          end

          private

          def entra_delegated_token
            Legion::Extensions::Identity::Entra::Helpers::TokenManager.load_token(:delegated)
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: 'Client#entra_delegated_token')
            nil
          end

          # Tunable knobs for the Retry-After middleware. Reads from the lex
          # settings under `microsoft_teams.client.retry.*` when available,
          # with safe defaults that match the middleware constants. Wires the
          # Lex logger in when present so retry / giveup events get structured
          # logging like the rest of the gem.
          def retry_after_options
            cfg = retry_after_settings || {}
            {
              max_retries:   cfg[:max_retries]   || cfg['max_retries']   || 3,
              max_wait:      cfg[:max_wait]      || cfg['max_wait']      || 60.0,
              jitter:        cfg[:jitter]        || cfg['jitter']        || 0.2,
              fallback_wait: cfg[:fallback_wait] || cfg['fallback_wait'] || 1.0,
              logger:        retry_after_logger
            }
          end

          def retry_after_settings
            return nil unless respond_to?(:settings, true)

            section = settings
            return nil unless section.respond_to?(:dig)

            section.dig(:client, :retry) || section.dig('client', 'retry')
          end

          def retry_after_logger
            log
          rescue StandardError => e
            warn("[microsoft_teams][client] retry_after_logger fallback: #{e.message}") if $DEBUG
            nil
          end
        end
      end
    end
  end
end
