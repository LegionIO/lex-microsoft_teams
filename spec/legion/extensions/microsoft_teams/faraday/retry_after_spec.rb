# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/microsoft_teams/faraday/retry_after'

RSpec.describe Legion::Extensions::MicrosoftTeams::Faraday::RetryAfter do
  let(:slept) { [] }
  let(:sleeper) { ->(seconds) { slept << seconds } }
  let(:logger) { instance_double('Logger', warn: nil, error: nil, debug: nil) }
  let(:fixed_now) { Time.utc(2026, 5, 27, 17, 0, 0) }
  let(:clock) { -> { fixed_now } }

  # Builds a Faraday connection with a Stubs adapter so we can drive responses
  # deterministically. The stub takes a list of [status, headers, body]
  # tuples and serves them in order for each retry attempt.
  # rubocop:disable Style/ArgumentsForwarding -- anonymous ** cannot be combined with
  # explicit kwargs at the call site, and the call site here passes explicit kwargs.
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

  describe 'success path' do
    it 'returns the response unchanged when status is not retryable' do
      conn = build_connection([[200, { 'Content-Type' => 'application/json' }, '{"value":[]}']])
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
      future = fixed_now + 7 # 7 seconds in the future
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
    it 'returns the throttled response after max_retries' do
      responses = Array.new(5) { [429, { 'Retry-After' => '1' }, '{"error":"throttled"}'] }
      conn = build_connection(responses, max_retries: 2)

      response = conn.get('/v1.0/me/chats')

      expect(response.status).to eq(429)
      expect(slept.length).to eq(2)
      expect(logger).to have_received(:error).at_least(:once)
    end

    it 'stops when cumulative wait would exceed max_wait' do
      responses = [
        [429, { 'Retry-After' => '40' }, ''],
        [429, { 'Retry-After' => '40' }, ''],
        [200, {}, '']
      ]
      conn = build_connection(responses, max_retries: 5, max_wait: 50.0)

      response = conn.get('/v1.0/me/chats')

      expect(response.status).to eq(429)
      expect(slept).to eq([40.0])
    end
  end

  describe 'retry status configuration' do
    it 'retries 503 by default-off and only retries 429 unless configured' do
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
  end

  describe 'malformed Retry-After' do
    it 'falls back to fallback_wait for garbage values' do
      conn = build_connection(
        [
          [429, { 'Retry-After' => 'not-a-thing' }, ''],
          [200, {}, '']
        ],
        fallback_wait: 3.0
      )

      conn.get('/v1.0/me/chats')

      expect(slept).to eq([3.0])
    end
  end
end
