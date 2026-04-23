# frozen_string_literal: true

require 'faraday'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        module Client
          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)

          def graph_connection(token: nil, api_url: 'https://graph.microsoft.com/v1.0', **_opts)
            token ||= settings&.dig(:auth, :delegated, :token)
            token ||= TokenCache.instance.cached_delegated_token if defined?(TokenCache)
            Faraday.new(url: api_url) do |conn|
              conn.request :json
              conn.response :json, content_type: /\bjson$/
              conn.headers['Authorization'] = "Bearer #{token}" if token
              conn.headers['Content-Type'] = 'application/json'
            end
          end

          def bot_connection(token: nil, service_url: 'https://smba.trafficmanager.net/teams/', **_opts)
            token ||= settings&.dig(:auth, :bot, :token)
            token ||= TokenCache.instance.cached_app_token if defined?(TokenCache)
            Faraday.new(url: service_url) do |conn|
              conn.request :json
              conn.response :json, content_type: /\bjson$/
              conn.headers['Authorization'] = "Bearer #{token}" if token
              conn.headers['Content-Type'] = 'application/json'
            end
          end

          def user_path(user_id = 'me')
            user_id == 'me' ? 'me' : "users/#{user_id}"
          end

          def oauth_connection(tenant_id: 'common', **_opts)
            Faraday.new(url: "https://login.microsoftonline.com/#{tenant_id}") do |conn|
              conn.request :url_encoded
              conn.response :json, content_type: /\bjson$/
            end
          end
        end
      end
    end
  end
end
