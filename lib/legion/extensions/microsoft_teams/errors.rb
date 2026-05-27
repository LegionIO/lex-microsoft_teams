# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Errors
        # Raised when Microsoft Graph (or the Bot Framework) throttles the
        # caller and the retry policy has been exhausted, or when an actor
        # wants to surface a throttle event without retrying further.
        #
        # `retry_after` carries the last advertised Retry-After interval
        # (in seconds) as parsed from the upstream header. **It is nil when
        # the server returned no Retry-After header or one we could not
        # parse** — callers must check `retry_after_known?` before treating
        # the value as a server directive. Conflating "header missing" with
        # "retry immediately" was the bug the original fleet outage exposed.
        class Throttled < StandardError
          attr_reader :status, :retry_after, :request, :attempts

          # @param status [Integer]      the upstream HTTP status (e.g. 429)
          # @param retry_after [Float, Integer, nil] seconds the server
          #   advised waiting, or nil if the header was absent/unparseable
          # @param request [String, nil] the path or URL that was throttled
          # @param attempts [Integer, nil] how many retries the middleware
          #   tried before giving up; nil means "not tracked"
          def initialize(status:, retry_after: nil, request: nil, attempts: nil)
            @status      = coerce_status(status)
            @retry_after = coerce_retry_after(retry_after)
            @request     = request
            @attempts    = attempts.nil? ? nil : Integer(attempts)
            super(build_message)
          end

          # @return [Boolean] true when the upstream advised a specific wait
          #   interval; false when the header was missing or unparseable. Use
          #   this to decide whether to honor the wait verbatim or apply a
          #   local policy default before re-scheduling.
          def retry_after_known?
            !@retry_after.nil?
          end

          private

          def coerce_status(value)
            Integer(value)
            # rubocop:disable Legion/RescueLogging/NoCapture
            # No logger available during exception construction; we re-raise
            # with a clearer message instead.
          rescue ArgumentError, TypeError
            raise ArgumentError, "Throttled status must be an Integer, got #{value.inspect}"
            # rubocop:enable Legion/RescueLogging/NoCapture
          end

          def coerce_retry_after(value)
            return nil if value.nil?

            seconds = Float(value)
            seconds.negative? ? 0.0 : seconds
            # rubocop:disable Legion/RescueLogging/NoCapture
            # Unparseable retry_after intentionally collapses to nil so the
            # public `retry_after_known?` predicate is the single source of
            # truth for "did the server give us usable guidance." Logging
            # belongs at the parse site (Faraday::RetryAfter), not here.
          rescue ArgumentError, TypeError
            nil
            # rubocop:enable Legion/RescueLogging/NoCapture
          end

          def build_message
            parts = ["Microsoft Graph throttled (HTTP #{@status})"]
            parts << "after #{@attempts} attempt(s)" if @attempts
            parts << if retry_after_known?
                       "retry_after=#{format('%.2f', @retry_after)}s"
                     else
                       'retry_after=unknown'
                     end
            parts << "request=#{@request}" if @request
            parts.join('; ')
          end
        end
      end
    end
  end
end
