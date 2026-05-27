# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Errors
        # Raised when Microsoft Graph (or Bot Framework) throttles the caller
        # and the retry policy has been exhausted, or when an actor wants to
        # surface a throttle event without retrying further.
        #
        # Carries the last advertised Retry-After interval (in seconds) so
        # callers can defer their next scheduled run instead of re-firing on
        # the standard cadence.
        class Throttled < StandardError
          attr_reader :status, :retry_after, :request, :attempts

          def initialize(status:, retry_after:, request: nil, attempts: nil)
            @status      = status
            @retry_after = retry_after.to_f
            @request     = request
            @attempts    = attempts
            super(build_message)
          end

          private

          def build_message
            parts = ["Microsoft Graph throttled (HTTP #{@status})"]
            parts << "after #{@attempts} attempt(s)" if @attempts
            parts << "retry_after=#{format('%.2f', @retry_after)}s"
            parts << "request=#{@request}" if @request
            parts.join('; ')
          end
        end
      end
    end
  end
end
