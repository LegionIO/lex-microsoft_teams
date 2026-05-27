# frozen_string_literal: true

require 'faraday'
require 'time'

module Legion
  module Extensions
    module MicrosoftTeams
      module Faraday
        # Faraday middleware that retries throttled responses (HTTP 429 by
        # default, optionally 503/504) honoring the upstream Retry-After
        # header per RFC 7231 §7.1.3.
        #
        # Retry-After is parsed in two forms:
        #
        # * delta-seconds (e.g. "120")           — used as-is
        # * HTTP-date    (e.g. "Wed, 27 May 2026 12:00:00 GMT")
        #                                          — converted to delta from
        #                                            current UTC, clamped to >= 0
        #
        # The advertised wait is jittered by ±(jitter * wait) to avoid
        # thundering-herd behavior across multiple instances sharing one Entra
        # app registration's Graph quota.
        #
        # If max_retries is reached, or cumulative wait exceeds max_wait, the
        # last throttled response is returned unchanged — callers are expected
        # to translate that into a typed `Errors::Throttled` (see
        # `Helpers::GraphClient#handle_graph_response`).
        class RetryAfter < ::Faraday::Middleware
          DEFAULT_MAX_RETRIES    = 3
          DEFAULT_MAX_WAIT       = 60.0
          DEFAULT_JITTER         = 0.2
          DEFAULT_FALLBACK_WAIT  = 1.0
          DEFAULT_RETRY_STATUSES = [429].freeze

          def initialize(app, # rubocop:disable Metrics/ParameterLists
                         max_retries: DEFAULT_MAX_RETRIES,
                         max_wait: DEFAULT_MAX_WAIT,
                         jitter: DEFAULT_JITTER,
                         fallback_wait: DEFAULT_FALLBACK_WAIT,
                         retry_statuses: DEFAULT_RETRY_STATUSES,
                         sleeper: ->(seconds) { sleep(seconds) },
                         logger: nil,
                         clock: -> { Time.now.utc })
            super(app)
            @max_retries    = Integer(max_retries)
            @max_wait       = Float(max_wait)
            @jitter         = Float(jitter)
            @fallback_wait  = Float(fallback_wait)
            @retry_statuses = Array(retry_statuses).map(&:to_i).freeze
            @sleeper        = sleeper
            @logger         = logger
            @clock          = clock
          end

          def call(env)
            attempts   = 0
            total_wait = 0.0

            loop do
              response = @app.call(env.dup)
              return response unless retryable?(response.status)

              wait = compute_wait(response)

              if attempts >= @max_retries || (total_wait + wait) > @max_wait
                log_giveup(env, response, attempts, total_wait)
                return response
              end

              attempts   += 1
              total_wait += wait
              log_retry(env, response, wait, attempts)
              @sleeper.call(wait)
            end
          end

          private

          def retryable?(status)
            @retry_statuses.include?(status.to_i)
          end

          def compute_wait(response)
            raw     = retry_after_header(response)
            seconds = parse_retry_after(raw)
            seconds = @fallback_wait if seconds.nil? || seconds.negative?
            apply_jitter(seconds)
          end

          def retry_after_header(response)
            headers = response_headers(response)
            return nil unless headers

            headers['Retry-After'] ||
              headers['retry-after'] ||
              headers['RETRY-AFTER']
          end

          # Faraday's Response exposes headers via #headers; some test
          # doubles may not, so look in both common places.
          def response_headers(response)
            if response.respond_to?(:headers) && response.headers
              response.headers
            elsif response.respond_to?(:response_headers)
              response.response_headers
            end
          end

          # Returns parsed seconds, or nil if the header is unusable.
          # Numeric form takes precedence over HTTP-date.
          def parse_retry_after(header)
            return nil if header.nil?

            value = header.to_s.strip
            return nil if value.empty?
            return value.to_f if value.match?(/\A\d+(\.\d+)?\z/)

            begin
              target = Time.httpdate(value).utc
              [(target - @clock.call), 0.0].max
            rescue ArgumentError => e
              @logger&.debug("[microsoft_teams][retry_after] failed to parse Retry-After=#{value.inspect}: #{e.message}")
              nil
            end
          end

          def apply_jitter(seconds)
            return seconds if @jitter.zero?

            spread = seconds * @jitter
            offset = ((rand * 2.0) - 1.0) * spread
            wait   = seconds + offset
            wait.negative? ? 0.0 : wait
          end

          def log_retry(env, response, wait, attempts)
            return unless @logger

            @logger.warn(
              "[microsoft_teams][retry_after] status=#{response.status} " \
              "method=#{env.method.to_s.upcase} path=#{env.url.path} " \
              "wait=#{format('%.2f', wait)}s attempt=#{attempts}"
            )
          end

          def log_giveup(env, response, attempts, total_wait)
            return unless @logger

            @logger.error(
              "[microsoft_teams][retry_after] giving up; status=#{response.status} " \
              "method=#{env.method.to_s.upcase} path=#{env.url.path} " \
              "attempts=#{attempts} total_wait=#{format('%.2f', total_wait)}s"
            )
          end
        end
      end
    end
  end
end
