# frozen_string_literal: true

require 'monitor'
require 'legion/extensions/microsoft_teams/errors'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        # Mixin that lets an `Actors::Every`-style poller honour a Graph
        # throttle by *deferring its own next run* instead of re-firing on
        # its fixed timer interval.
        #
        # Background: `Faraday::RetryAfter` raises `Errors::Throttled`
        # centrally when it exhausts retries (or when the advertised wait
        # alone exceeds the retry budget), and `Faraday::ThrottleCircuit`
        # opens a shared circuit so the whole fleet stops hammering a quota
        # that Graph has already flagged. But the actors that *drive* those
        # calls schedule themselves with a `Concurrent::TimerTask` whose
        # `execution_interval` is fixed at boot. Catching `Throttled` in a
        # `rescue` block stops the current tick, but the next tick still
        # fires on the original cadence — so a poller on a 30–300s interval
        # keeps walking straight back into an open circuit, emitting an
        # ERROR every interval and contributing nothing but log noise (and,
        # via the shared circuit, refreshing the block for cheaper callers).
        #
        # This mixin closes that gap. An actor wraps its Graph work in
        # {#with_throttle_deferral}. On `Errors::Throttled` it records a
        # "suppress until" instant of `now + retry_after` (falling back to a
        # bounded default when the server gave no usable `Retry-After`).
        # Subsequent ticks short-circuit via {#throttle_suppressed?} until
        # that instant passes, so the actor effectively reschedules itself
        # at `now + retry_after` rather than `now + interval` — exactly the
        # behaviour the throttle integration spec and the 0.6.51 CHANGELOG
        # flagged as the outstanding follow-up.
        #
        # State is per-actor-instance and guarded by a monitor because an
        # actor's `manual` runs on a `Concurrent` thread-pool worker. The
        # mixin reads the carried `retry_after` only when
        # `retry_after_known?` is true; otherwise it applies
        # {DEFAULT_DEFERRAL} so a throttle with a missing/garbage header
        # still backs the poller off rather than letting it spin.
        module ThrottleAware
          # Fallback deferral (seconds) used when a `Throttled` carries no
          # usable `retry_after` (header absent or unparseable). One minute
          # matches Microsoft Graph's documented typical Retry-After and the
          # circuit middleware's `DEFAULT_FALLBACK_TTL`.
          DEFAULT_DEFERRAL = 60.0

          # Hard ceiling (seconds) on a single deferral so a pathological
          # advertised `Retry-After` can't park a poller for an unbounded
          # time. Mirrors the circuit middleware's 600s cap in
          # `ThrottleCircuit#set_hard_circuit`.
          MAX_DEFERRAL = 600.0

          # Run `block` unless the actor is currently deferring after a
          # recent throttle. If a `Throttled` escapes the block, record the
          # deferral window and swallow it (the throttle has already been
          # logged at the middleware/circuit layer; re-raising would just
          # trip the actor's generic `rescue StandardError` and double-log).
          #
          # @param now [Time] injectable clock for deterministic tests
          # @return [Object, nil] the block's value, or nil when suppressed
          #   or when a throttle was caught
          def with_throttle_deferral(now: Time.now)
            if throttle_suppressed?(now: now)
              log_throttle_skip(now: now)
              return nil
            end

            yield
          rescue Legion::Extensions::MicrosoftTeams::Errors::Throttled => e
            defer_after_throttle(e, now: now)
            nil
          end

          # @return [Boolean] true while the actor is inside a deferral
          #   window opened by a previous throttle.
          def throttle_suppressed?(now: Time.now)
            until_at = throttled_until
            !until_at.nil? && now < until_at
          end

          # The instant before which the actor should not poll again, or nil
          # if no deferral is active. Thread-safe read.
          def throttled_until
            throttle_monitor.synchronize { @throttled_until }
          end

          # Seconds remaining in the current deferral window (0.0 if none /
          # elapsed). Useful for logging and for tests.
          def throttle_remaining(now: Time.now)
            until_at = throttled_until
            return 0.0 if until_at.nil?

            remaining = until_at - now
            remaining.positive? ? remaining : 0.0
          end

          # Open (or extend) a deferral window of `seconds` from `now`. A
          # later throttle never *shortens* an existing window — we keep the
          # furthest-out instant so overlapping throttles compose safely.
          def defer_for(seconds, now: Time.now)
            window = clamp_deferral(seconds)
            target = now + window
            throttle_monitor.synchronize do
              @throttled_until = if @throttled_until.nil? || target > @throttled_until
                                   target
                                 else
                                   @throttled_until
                                 end
            end
            window
          end

          # Clear any active deferral. Called implicitly is unnecessary —
          # {#throttle_suppressed?} expires on its own once the clock passes
          # `throttled_until` — but exposed for tests and explicit resets.
          def reset_throttle_deferral
            throttle_monitor.synchronize { @throttled_until = nil }
          end

          private

          def defer_after_throttle(error, now: Time.now)
            seconds = deferral_seconds_for(error)
            window  = defer_for(seconds, now: now)
            log.warn(
              "[microsoft_teams][throttle_defer] #{actor_label}: " \
              "deferring next run #{format('%.1f', window)}s " \
              "(retry_after=#{error.retry_after_known? ? format('%.1f', error.retry_after) : 'unknown'} " \
              "path=#{error.request})"
            )
          end

          # Short, log-friendly name for the including actor. Falls back to
          # the full class string for anonymous classes (whose `name` is
          # nil), so the log line never raises on `name.split`.
          def actor_label
            (self.class.name || self.class.to_s).split('::').last
          end

          # Prefer the server-advised wait; fall back to {DEFAULT_DEFERRAL}
          # only when the header was absent or unparseable.
          def deferral_seconds_for(error)
            if error.respond_to?(:retry_after_known?) && error.retry_after_known?
              error.retry_after
            else
              DEFAULT_DEFERRAL
            end
          end

          def clamp_deferral(seconds)
            value = begin
              Float(seconds)
              # rubocop:disable Legion/RescueLogging/NoCapture
              # Pure coercion fallback for a non-numeric deferral; the value
              # is bounded immediately below, so a bad input degrades to the
              # default rather than warranting its own log line.
            rescue ArgumentError, TypeError
              DEFAULT_DEFERRAL
              # rubocop:enable Legion/RescueLogging/NoCapture
            end
            value = DEFAULT_DEFERRAL if value <= 0
            [value, MAX_DEFERRAL].min
          end

          def log_throttle_skip(now: Time.now)
            log.debug(
              "[microsoft_teams][throttle_defer] #{actor_label}: " \
              "skipping run, #{format('%.1f', throttle_remaining(now: now))}s deferral remaining"
            )
          end

          def throttle_monitor
            # `||=` is safe here: the first tick of an actor runs before any
            # concurrent re-entry (the `Every` base guards re-entry with its
            # own AtomicBoolean), so the monitor is initialised single-threaded.
            @throttle_monitor ||= Monitor.new
          end
        end
      end
    end
  end
end
