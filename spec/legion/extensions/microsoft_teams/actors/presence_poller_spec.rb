# frozen_string_literal: true

require 'spec_helper'

# PresencePoller subclasses Actors::Every; the real base starts a
# Concurrent::TimerTask in #initialize. Use .allocate everywhere so no timer
# is ever scheduled — we drive #manual directly and assert on the deferral
# state the ThrottleAware mixin maintains.
require 'legion/extensions/microsoft_teams/errors'
require 'legion/extensions/microsoft_teams/actors/presence_poller'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::PresencePoller do
  let(:actor) { described_class.allocate }
  let(:conn)  { instance_double(Faraday::Connection) }
  let(:t0)    { Time.utc(2026, 5, 29, 12, 0, 0) }

  before do
    allow(actor).to receive(:delegated_token).and_return('tok')
    allow(actor).to receive(:graph_connection).and_return(conn)
    # Quiet logger; handle_exception is the actor's outer StandardError sink.
    logger = instance_double('Logger', debug: nil, info: nil, warn: nil, error: nil)
    allow(actor).to receive(:log).and_return(logger)
    allow(actor).to receive(:handle_exception)
  end

  def throttled(retry_after:)
    Legion::Extensions::MicrosoftTeams::Errors::Throttled.new(
      status: 429, retry_after: retry_after, request: '/v1.0/me/presence', attempts: 0
    )
  end

  describe '#manual under Graph throttle' do
    it 'opens a deferral window of retry_after seconds when the presence call is throttled' do
      allow(conn).to receive(:get).with('me/presence').and_raise(throttled(retry_after: 47.0))

      actor.with_throttle_deferral(now: t0) { actor.send(:poll_presence) }

      expect(actor.throttled_until).to eq(t0 + 47.0)
      expect(actor.throttle_suppressed?(now: t0 + 46)).to be(true)
      expect(actor.throttle_suppressed?(now: t0 + 48)).to be(false)
    end

    it 'does NOT make a Graph call on the next tick while still deferring' do
      call_count = 0
      allow(conn).to receive(:get).with('me/presence') do
        call_count += 1
        raise throttled(retry_after: 60.0)
      end

      # First tick: throttled, opens a 60s window.
      actor.with_throttle_deferral(now: t0) { actor.send(:poll_presence) }
      # Second tick 5s later: must short-circuit before touching Graph.
      actor.with_throttle_deferral(now: t0 + 5) { actor.send(:poll_presence) }

      expect(call_count).to eq(1) # only the first tick reached the Graph call
    end

    it 'polls again once the deferral window has elapsed' do
      call_count = 0
      allow(conn).to receive(:get).with('me/presence') do
        call_count += 1
        # First call throttles; a later call (after the window) returns 200.
        raise throttled(retry_after: 30.0) if call_count == 1

        instance_double(Faraday::Response, body: { 'availability' => 'Available', 'activity' => 'Available' })
      end

      actor.with_throttle_deferral(now: t0)       { actor.send(:poll_presence) }   # tick 1: throttled
      actor.with_throttle_deferral(now: t0 + 10)  { actor.send(:poll_presence) }   # tick 2: suppressed
      actor.with_throttle_deferral(now: t0 + 31)  { actor.send(:poll_presence) }   # tick 3: window elapsed

      expect(call_count).to eq(2) # tick 1 and tick 3 hit Graph; tick 2 was suppressed
    end
  end

  describe '#manual without throttle' do
    it 'polls presence and never opens a deferral window' do
      response = instance_double(Faraday::Response,
                                 body: { 'availability' => 'Available', 'activity' => 'Available' })
      allow(conn).to receive(:get).with('me/presence').and_return(response)

      actor.manual

      expect(actor.throttle_suppressed?).to be(false)
      expect(actor.throttled_until).to be_nil
    end
  end
end
