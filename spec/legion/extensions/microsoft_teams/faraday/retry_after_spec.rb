# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/microsoft_teams/faraday/retry_after'
require 'legion/extensions/microsoft_teams/errors'

RSpec.describe Legion::Extensions::MicrosoftTeams::Faraday::RetryAfter do
  let(:slept)     { [] }
  let(:sleeper)   { ->(seconds) { slept << seconds } }
  let(:logger)    { instance_double('Logger', warn: nil, error: nil, debug: nil) }
  let(:fixed_now) { Time.utc(2026, 5, 27, 17, 0, 0) }
  let(:clock)     { -> { fixed_now } }

  # Builds a Faraday connection backed by the test adapter. `responses` is a
  # list of [status, headers, body] tuples served in order — one per call.
  # rubocop:disable Style/ArgumentsForwarding -- anonymous ** cannot combine with
  # explicit kwargs at the call site.
  def build_connection(responses, **opts)
    stubs = Faraday::Adapter::Test::Stubs.new

    responses.each do |status, headers, body|
      stubs.get('/v1.0/me/chats') do
        [status, headers, body]
      end
    end

    Faraday.new(url: 'https://graph.microsoft.com') do |conn|
      conn.use described_class, sleeper: sleeper, logger: logger, clock: clock, jitter: 0.0, **opts
      conn.adapter :test, stubs
    end
  end
  # rubocop:enable Style/ArgumentsForwarding

  describe '.parse_header' do
    it 'returns nil for nil input' do
      expect(described_class.parse_header(nil)).to be_nil
    end

    it 'returns nil for empty string' do
      expect(described_class.parse_header('')).to be_nil
      expect(described_class.parse_header('   ')).to be_nil
    end

    it 'parses delta-seconds integers' do
      expect(described_class.parse_header('120')).to eq(120.0)
    end

    it 'parses fractional delta-seconds' do
      expect(described_class.parse_header('0.5')).to eq(0.5)
    end

    it 'parses HTTP-date and computes delta from clock' do
      now    = Time.utc(2026, 5, 27, 12, 0, 0)
      target = now + 30
      result = described_class.parse_header(target.httpdate, clock: -> { now })

      expect(result).to be_within(0.01).of(30.0)
    end

    it 'clamps past HTTP-dates to zero' do
      now  = Time.utc(2026, 5, 27, 12, 0, 0)
      past = now - 60

      expect(described_class.parse_header(past.httpdate, clock: -> { now })).to eq(0.0)
    end

    it 'returns nil for garbage' do
      expect(described_class.parse_header('not-a-thing')).to be_nil
      expect(described_class.parse_header('Mon BAD DATE')).to be_nil
    end
  end

  describe 'success path' do
    it 'returns the response unchanged when status is not retryable' do
      conn     = build_connection([[200, { 'Content-Type' => 'application/json' }, '{"value":[]}']])
      response = conn.get('/v1.0/me/chats')

      expect(response.status).to eq(200)
      expect(slept).to be_empty
    end
  end

  describe '429 with Retry-After in delta-seconds form' do
    it 'sleeps for the advertised seconds and retries' do
      conn = build_connection([
                                [429, { 'Retry-After' => '2' }, '{"error":"throttled"}'],
                                [200, {}, '{"ok":true}']
                              ])

      response = conn.get('/v1.0/me/chats')

      expect(response.status).to eq(200)
      expect(slept).to eq([2.0])
    end

    it 'parses fractional seconds' do
      conn = build_connection([
                                [429, { 'Retry-After' => '0.5' }, ''],
                                [200, {}, '']
                              ])

      conn.get('/v1.0/me/chats')

      expect(slept).to eq([0.5])
    end
  end

  describe '429 with Retry-After in HTTP-date form' do
    it 'computes seconds from clock to httpdate target' do
      future = fixed_now + 7
      conn = build_connection([
                                [429, { 'Retry-After' => future.httpdate }, ''],
                                [200, {}, '']
                              ])

      conn.get('/v1.0/me/chats')

      expect(slept.first).to be_within(0.01).of(7.0)
    end

    it 'clamps to zero when the httpdate is in the past' do
      past = fixed_now - 30
      conn = build_connection([
                                [429, { 'Retry-After' => past.httpdate }, ''],
                                [200, {}, '']
                              ])

      conn.get('/v1.0/me/chats')

      expect(slept).to eq([0.0])
    end
  end

  describe '429 without Retry-After' do
    it 'falls back to fallback_wait' do
      conn = build_connection(
        [
          [429, {}, ''],
          [200, {}, '']
        ],
        fallback_wait: 2.5
      )

      conn.get('/v1.0/me/chats')

      expect(slept).to eq([2.5])
    end
  end

  describe 'retry exhaustion' do
    it 'raises Errors::Throttled after max_retries with carried advertised retry_after' do
      responses = Array.new(5) { [429, { 'Retry-After' => '7' }, '{"error":"throttled"}'] }
      conn = build_connection(responses, max_retries: 2)

      raised = nil
      begin
        conn.get('/v1.0/me/chats')
      rescue Legion::Extensions::MicrosoftTeams::Errors::Throttled => e
        raised = e
      end

      expect(raised).not_to be_nil
      expect(raised.status).to eq(429)
      expect(raised.retry_after).to eq(7.0)
      expect(raised.retry_after_known?).to be(true)
      expect(raised.attempts).to eq(2)
      expect(raised.request).to eq('/v1.0/me/chats')
      expect(slept.length).to eq(2)
      expect(logger).to have_received(:error).at_least(:once)
    end

    it 'gives up without sleeping when first Retry-After exceeds max_wait' do
      conn = build_connection(
        [[429, { 'Retry-After' => '600' }, '{"error":"throttled"}']],
        max_retries: 5,
        max_wait:    60.0
      )

      expect { conn.get('/v1.0/me/chats') }.to raise_error(
        Legion::Extensions::MicrosoftTeams::Errors::Throttled
      ) do |e|
        expect(e.retry_after).to eq(600.0)
        expect(e.attempts).to eq(0)
      end

      expect(slept).to be_empty
    end

    it 'stops when cumulative wait would exceed max_wait' do
      responses = [
        [429, { 'Retry-After' => '40' }, ''],
        [429, { 'Retry-After' => '40' }, '']
      ]
      conn = build_connection(responses, max_retries: 5, max_wait: 50.0)

      expect { conn.get('/v1.0/me/chats') }.to raise_error(
        Legion::Extensions::MicrosoftTeams::Errors::Throttled
      )
      expect(slept).to eq([40.0])
    end

    it 'raises Throttled with retry_after=nil when server gave no usable header' do
      responses = Array.new(5) { [429, {}, ''] }
      conn = build_connection(responses, max_retries: 1, fallback_wait: 0.1)

      raised = nil
      begin
        conn.get('/v1.0/me/chats')
      rescue Legion::Extensions::MicrosoftTeams::Errors::Throttled => e
        raised = e
      end

      expect(raised.retry_after).to be_nil
      expect(raised.retry_after_known?).to be(false)
    end

    it 'raises Throttled with retry_after=nil when header was unparseable garbage' do
      responses = Array.new(5) { [429, { 'Retry-After' => 'never' }, ''] }
      conn = build_connection(responses, max_retries: 1, fallback_wait: 0.1)

      raised = nil
      begin
        conn.get('/v1.0/me/chats')
      rescue Legion::Extensions::MicrosoftTeams::Errors::Throttled => e
        raised = e
      end

      expect(raised.retry_after).to be_nil
      expect(logger).to have_received(:warn).with(/unparseable Retry-After/).at_least(:once)
    end
  end

  describe 'retry status configuration' do
    it 'does not retry 503 by default' do
      conn = build_connection(
        [
          [503, { 'Retry-After' => '1' }, ''],
          [200, {}, '']
        ]
      )

      response = conn.get('/v1.0/me/chats')

      expect(response.status).to eq(503)
      expect(slept).to be_empty
    end

    it 'retries 503 when included in retry_statuses' do
      conn = build_connection(
        [
          [503, { 'Retry-After' => '1' }, ''],
          [200, {}, '']
        ],
        retry_statuses: [429, 503]
      )

      response = conn.get('/v1.0/me/chats')

      expect(response.status).to eq(200)
      expect(slept).to eq([1.0])
    end

    it 'raises Throttled with the 503 status when 503 is opt-in and exhausted' do
      responses = Array.new(5) { [503, { 'Retry-After' => '1' }, ''] }
      conn = build_connection(responses, retry_statuses: [429, 503], max_retries: 1)

      raised = nil
      begin
        conn.get('/v1.0/me/chats')
      rescue Legion::Extensions::MicrosoftTeams::Errors::Throttled => e
        raised = e
      end

      expect(raised.status).to eq(503)
    end
  end

  describe 'jitter' do
    it 'keeps the wait within +/- jitter*wait of the advertised value' do
      conn = build_connection(
        [
          [429, { 'Retry-After' => '10' }, ''],
          [200, {}, '']
        ],
        jitter: 0.2
      )

      conn.get('/v1.0/me/chats')

      expect(slept.first).to be >= 8.0
      expect(slept.first).to be <= 12.0
    end

    it 'never produces a negative wait' do
      100.times do
        conn = build_connection(
          [
            [429, { 'Retry-After' => '0' }, ''],
            [200, {}, '']
          ],
          jitter: 0.5
        )
        conn.get('/v1.0/me/chats')
      end

      expect(slept).to all(be >= 0.0)
    end

    it 'returns exactly 0.0 when advertised is 0 and jitter is 0' do
      conn = build_connection(
        [
          [429, { 'Retry-After' => '0' }, ''],
          [200, {}, '']
        ],
        jitter: 0.0
      )

      conn.get('/v1.0/me/chats')

      expect(slept).to eq([0.0])
    end
  end

  describe 'logging resilience' do
    it 'does not crash the retry loop if the logger raises in log_retry' do
      raising_logger = double('Logger')
      allow(raising_logger).to receive(:warn).and_raise(StandardError, 'sink down')
      allow(raising_logger).to receive(:error)

      conn = Faraday.new(url: 'https://graph.microsoft.com') do |c|
        c.use described_class,
              sleeper: sleeper,
              logger:  raising_logger,
              clock:   clock,
              jitter:  0.0
        c.adapter :test do |stubs|
          stubs.get('/v1.0/me/chats') { [429, { 'Retry-After' => '1' }, ''] }
          stubs.get('/v1.0/me/chats') { [200, {}, ''] }
        end
      end

      expect { conn.get('/v1.0/me/chats') }.not_to raise_error
    end
  end
end
