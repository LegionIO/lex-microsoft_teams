# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/microsoft_teams/helpers/throttle_aware'
require 'legion/extensions/microsoft_teams/errors'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::ThrottleAware do
  # Minimal host: includes the mixin and exposes a stub logger so we can
  # assert on deferral / skip log lines without the full Lex helper chain.
  let(:host_class) do
    Class.new do
      include Legion::Extensions::MicrosoftTeams::Helpers::ThrottleAware

      def log
        @log ||= Struct.new(:warns, :debugs) do
          def warn(msg)  = warns << msg
          def debug(msg) = debugs << msg
        end.new([], [])
      end
    end
  end

  let(:host) { host_class.new }
  let(:t0)   { Time.utc(2026, 5, 29, 12, 0, 0) }

  def throttled(retry_after: nil, request: '/v1.0/me/presence')
    Legion::Extensions::MicrosoftTeams::Errors::Throttled.new(
      status: 429, retry_after: retry_after, request: request, attempts: 0
    )
  end

  describe '#with_throttle_deferral' do
    it 'runs the block and returns its value when not throttled' do
      result = host.with_throttle_deferral(now: t0) { :ran }
      expect(result).to eq(:ran)
      expect(host.throttle_suppressed?(now: t0)).to be(false)
    end

    it 'opens a deferral window of retry_after seconds when the block raises Throttled' do
      host.with_throttle_deferral(now: t0) { raise throttled(retry_after: 47.0) }

      # Still suppressed 1s before the window closes...
      expect(host.throttle_suppressed?(now: t0 + 46)).to be(true)
      # ...and open again once it elapses.
      expect(host.throttle_suppressed?(now: t0 + 47.001)).to be(false)
      expect(host.throttled_until).to eq(t0 + 47.0)
    end

    it 'swallows the Throttled (does not re-raise) so the actor rescue does not double-log' do
      expect do
        host.with_throttle_deferral(now: t0) { raise throttled(retry_after: 10.0) }
      end.not_to raise_error
    end

    it 'skips the block while suppressed and returns nil' do
      host.with_throttle_deferral(now: t0) { raise throttled(retry_after: 30.0) }

      ran = false
      result = host.with_throttle_deferral(now: t0 + 5) { ran = true }
      expect(ran).to be(false)
      expect(result).to be_nil
    end

    it 'runs again once the deferral window elapses' do
      host.with_throttle_deferral(now: t0) { raise throttled(retry_after: 30.0) }

      ran = false
      host.with_throttle_deferral(now: t0 + 31) { ran = true }
      expect(ran).to be(true)
    end

    it 'falls back to DEFAULT_DEFERRAL when retry_after is unknown' do
      host.with_throttle_deferral(now: t0) { raise throttled(retry_after: nil) }
      expect(host.throttled_until).to eq(t0 + described_class::DEFAULT_DEFERRAL)
    end

    it 'clamps an excessive retry_after to MAX_DEFERRAL' do
      host.with_throttle_deferral(now: t0) { raise throttled(retry_after: 99_999.0) }
      expect(host.throttled_until).to eq(t0 + described_class::MAX_DEFERRAL)
    end

    it 'logs a throttle_defer warning carrying retry_after and path' do
      host.with_throttle_deferral(now: t0) { raise throttled(retry_after: 12.0, request: '/v1.0/me/presence') }
      expect(host.log.warns.join).to include('throttle_defer', 'retry_after=12.0', '/v1.0/me/presence')
    end
  end

  describe '#defer_for' do
    it 'never shortens an existing further-out window' do
      host.defer_for(60, now: t0)        # window closes at t0+60
      host.defer_for(5,  now: t0)        # shorter — must be ignored
      expect(host.throttled_until).to eq(t0 + 60)
    end

    it 'extends the window when the new deferral reaches further out' do
      host.defer_for(10, now: t0)
      host.defer_for(40, now: t0 + 5)    # closes at t0+45 > t0+10
      expect(host.throttled_until).to eq(t0 + 45)
    end
  end

  describe '#throttle_remaining' do
    it 'reports seconds left in the window and 0 once elapsed' do
      host.defer_for(30, now: t0)
      expect(host.throttle_remaining(now: t0 + 10)).to be_within(0.001).of(20.0)
      expect(host.throttle_remaining(now: t0 + 31)).to eq(0.0)
    end
  end

  describe '#reset_throttle_deferral' do
    it 'clears an active window' do
      host.defer_for(60, now: t0)
      host.reset_throttle_deferral
      expect(host.throttle_suppressed?(now: t0 + 1)).to be(false)
    end
  end
end
