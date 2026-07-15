# frozen_string_literal: true

require 'faraday'
require 'time'
require 'legion/extensions/microsoft_teams/errors'

module Legion
  module Extensions
    module MicrosoftTeams
      module Faraday
        # Faraday middleware that retries throttled responses honoring the
        # upstream Retry-After header per RFC 9110 §10.2.3 (originally
        # specified in RFC 7231 §7.1.3). Retries HTTP 429 by default; 503
        # and 504 are opt-in via `retry_statuses:`.
        #
        # Retry-After is parsed in two forms:
        #
        # * delta-seconds  (e.g. "120")               — used as-is
        # * HTTP-date      (e.g. "Wed, 27 May 2026 12:00:00 GMT")
        #                                              — converted to delta
        #                                                from current UTC,
        #                                                clamped to >= 0
        #
        # The advertised wait is jittered by ±(jitter * wait) to avoid
        # thundering-herd behavior across instances sharing one Entra app
        # registration's Graph quota.
        #
        # When `max_retries` is reached, or cumulative wait would exceed
        # `max_wait`, the middleware raises `Errors::Throttled` carrying
        # the last advertised Retry-After (nil if the header was missing or
        # unparseable), the final HTTP status, attempt count, and request
        # path. Raising centrally — rather than returning a raw 429 and
        # trusting every caller to detect it — is the difference between
        # one typed event the fleet can defer on, and 60+ runner callsites
        # that silently treat throttle envelopes as data.
        class RetryAfter < ::Faraday::Middleware
          DEFAULT_MAX_RETRIES    = 3
          DEFAULT_MAX_WAIT       = 60.0
          DEFAULT_JITTER         = 0.2
          DEFAULT_FALLBACK_WAIT  = 1.0
          DEFAULT_RETRY_STATUSES = [429].freeze

          # Parse an HTTP Retry-After header value.
          #
          # @param raw [String, nil] the raw header value
          # @param clock [#call] a callable returning current UTC Time,
          #   injectable for deterministic tests
          # @return [Float, nil] seconds to wait, or nil if `raw` is absent,
          #   empty, or neither a numeric delta nor a valid HTTP-date
          def self.parse_header(raw, clock: -> { Time.now.utc })
            return nil if raw.nil?

            value = raw.to_s.strip
            return nil if value.empty?
            return value.to_f if value.match?(/\A\d+(\.\d+)?\z/)

            begin
              target = Time.httpdate(value).utc
              [(target - clock.call), 0.0].max
              # rubocop:disable Legion/RescueLogging/NoCapture
              # Pure parser — no logger access. The instance method
              # `parse_advertised` warns on the same condition with full
              # context; logging twice would just be noise.
            rescue ArgumentError
              nil
              # rubocop:enable Legion/RescueLogging/NoCapture
            end
          end

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
            attempts          = 0
            total_wait        = 0.0
            last_advertised   = nil

            (@max_retries + 1).times do
              response = @app.call(env.dup)
              return response unless retryable?(response.status)

              last_advertised = parse_advertised(response)
              wait            = compute_wait(last_advertised)

              if attempts >= @max_retries || (total_wait + wait) > @max_wait
                log_giveup(env, response, attempts, total_wait)
                raise Errors::Throttled.new(
                  status:      response.status,
                  retry_after: last_advertised,
                  request:     request_path(env),
                  attempts:    attempts
                )
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

          # Parse the advertised Retry-After value from a response. Returns
          # nil if the header is missing or unparseable — callers branch on
          # nil to distinguish "no server guidance" from "retry now".
          def parse_advertised(response)
            raw = retry_after_header(response)
            parsed = self.class.parse_header(raw, clock: @clock)
            @logger&.warn("[microsoft_teams][retry_after] unparseable Retry-After=#{raw.inspect}") if raw && !raw.to_s.strip.empty? && parsed.nil?
            parsed
          end

          # Computes the actual wait the middleware will sleep before the
          # next attempt. Falls back to `@fallback_wait` only when the
          # server gave no usable guidance; jitter is always applied so
          # concurrent instances don't synchronize their retries.
          def compute_wait(advertised)
            seconds = advertised || @fallback_wait
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

          def apply_jitter(seconds)
            return seconds if @jitter.zero?

            spread = seconds * @jitter
            offset = ((rand * 2.0) - 1.0) * spread
            wait   = seconds + offset
            wait.negative? ? 0.0 : wait
          end

          def request_path(env)
            env.url.respond_to?(:path) ? env.url.path : env.url.to_s
            # rubocop:disable Legion/RescueLogging/NoCapture
            # Defensive fallback for malformed env.url; the path is only used
            # for log lines and error messages, never for control flow.
          rescue StandardError
            nil
            # rubocop:enable Legion/RescueLogging/NoCapture
          end

          def log_retry(env, response, wait, attempts)
            return unless @logger

            @logger.warn(
              "[microsoft_teams][retry_after] status=#{response.status} " \
              "method=#{env.method.to_s.upcase} path=#{request_path(env)} " \
              "wait=#{format('%.2f', wait)}s attempt=#{attempts}"
            )
          rescue StandardError => e
            warn("[microsoft_teams][retry_after] log_retry suppressed #{e.class}: #{e.message}")
          end

          def log_giveup(env, response, attempts, total_wait)
            return unless @logger

            @logger.error(
              "[microsoft_teams][retry_after] giving up; status=#{response.status} " \
              "method=#{env.method.to_s.upcase} path=#{request_path(env)} " \
              "attempts=#{attempts} total_wait=#{format('%.2f', total_wait)}s"
            )
          rescue StandardError => e
            warn("[microsoft_teams][retry_after] log_giveup suppressed #{e.class}: #{e.message}")
          end
        end
      end
    end
  end
end
