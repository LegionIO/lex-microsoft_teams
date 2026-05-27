# frozen_string_literal: true

require 'faraday'
require 'legion/extensions/microsoft_teams/errors'

module Legion
  module Extensions
    module MicrosoftTeams
      module Faraday
        class ThrottleCircuit < ::Faraday::Middleware
          CIRCUIT_KEY = 'microsoft_teams:graph:circuit:v1:global'
          DEFAULT_SOFT_PERCENTAGE = 0.8
          DEFAULT_SOFT_TTL = 60
          DEFAULT_FALLBACK_TTL = 60
          DEFAULT_INSIGHTS_TTL = 600

          def initialize(app,
                         soft_percentage: DEFAULT_SOFT_PERCENTAGE,
                         soft_ttl: DEFAULT_SOFT_TTL,
                         fallback_ttl: DEFAULT_FALLBACK_TTL,
                         insights_ttl: DEFAULT_INSIGHTS_TTL,
                         logger: nil)
            super(app)
            @soft_percentage = Float(soft_percentage)
            @soft_ttl = Integer(soft_ttl)
            @fallback_ttl = Integer(fallback_ttl)
            @insights_ttl = Integer(insights_ttl)
            @logger = logger
          end

          def call(env)
            remaining = circuit_remaining
            if remaining&.positive?
              path = request_path(env)
              @logger&.debug("[throttle_circuit] circuit open, #{remaining}s remaining, blocking #{path}")
              raise Errors::Throttled.new(
                status:      429,
                retry_after: remaining,
                request:     path,
                attempts:    0
              )
            end

            response = @app.call(env)
            check_throttle_percentage(env, response)
            response
          rescue Errors::Throttled => e
            set_hard_circuit(path: request_path(env), retry_after: e.retry_after)
            raise
          end

          private

          def circuit_remaining
            return nil unless cache_available?

            raw = Legion::Cache.get(CIRCUIT_KEY) # rubocop:disable Legion/HelperMigration/DirectCache
            return nil unless raw

            expires_at = raw.to_f
            remaining = expires_at - Time.now.to_f
            remaining.positive? ? remaining.ceil : nil
          rescue StandardError => e
            @logger&.debug("[throttle_circuit] circuit_remaining error: #{e.message}")
            nil
          end

          def check_throttle_percentage(env, response)
            headers = response_headers(response)
            return unless headers

            raw = headers['x-ms-throttle-limit-percentage'] ||
                  headers['X-Ms-Throttle-Limit-Percentage']
            return unless raw

            percentage = raw.to_f / 100.0
            return unless percentage >= @soft_percentage

            ttl = @soft_ttl
            path = request_path(env)
            @logger&.warn("[throttle_circuit] soft circuit: throttle=#{(percentage * 100).round}% " \
                          "path=#{path} ttl=#{ttl}s")
            set_circuit(ttl: ttl)
          end

          def set_hard_circuit(path:, retry_after:)
            ttl = if retry_after&.positive?
                    [retry_after.ceil, 600].min
                  else
                    classified_ttl(path)
                  end
            @logger&.warn("[throttle_circuit] hard circuit: path=#{path} ttl=#{ttl}s")
            set_circuit(ttl: ttl)
          end

          def classified_ttl(path)
            return @insights_ttl if path&.match?(%r{/me/people|/me/insights|aiInsights})
            return @fallback_ttl if path&.match?(/chats|channels|messages|presence|meetings/)

            @fallback_ttl
          end

          def set_circuit(ttl:)
            return unless cache_available?

            expires_at = Time.now.to_f + ttl
            Legion::Cache.set(CIRCUIT_KEY, expires_at.to_s, ttl: ttl, async: false) # rubocop:disable Legion/HelperMigration/DirectCache
          rescue StandardError => e
            @logger&.debug("[throttle_circuit] set_circuit error: #{e.message}")
          end

          def cache_available?
            defined?(Legion::Cache) && Legion::Cache.respond_to?(:get)
          end

          def request_path(env)
            env.url.respond_to?(:path) ? env.url.path : env.url.to_s
          rescue StandardError => e
            @logger&.debug("[throttle_circuit] request_path error: #{e.message}")
            nil
          end

          def response_headers(response)
            if response.respond_to?(:headers) && response.headers
              response.headers
            elsif response.respond_to?(:response_headers)
              response.response_headers
            end
          end
        end
      end
    end
  end
end
