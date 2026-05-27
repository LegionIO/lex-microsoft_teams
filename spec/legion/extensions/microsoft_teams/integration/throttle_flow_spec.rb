# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/microsoft_teams/helpers/client'
require 'legion/extensions/microsoft_teams/helpers/graph_client'
require 'legion/extensions/microsoft_teams/errors'

# End-to-end coverage: drive the actual Faraday middleware stack assembled
# by `graph_connection`, route the response through `handle_graph_response`,
# and assert the typed Throttled raises with the *last advertised* server
# Retry-After value carried verbatim. This is the path that protects every
# runner that uses `graph_get` / `graph_paginate` from the silent-429
# failure mode the parent issue describes.
RSpec.describe 'Throttle flow integration' do
  let(:host_class) do
    Class.new do
      include Legion::Extensions::MicrosoftTeams::Helpers::Client
      include Legion::Extensions::MicrosoftTeams::Helpers::GraphClient

      attr_writer :sleeper, :stubs

      def settings
        # No-sleep test config: 0 jitter so we don't flake on bounds, tiny
        # fallback_wait so an unparseable header path also completes fast,
        # explicit max_retries so the test asserts what it intends.
        { client: { retry: { max_retries: 2, jitter: 0.0, fallback_wait: 0.0 } } }
      end

      private

      # Override the connection builder to inject a captured sleeper +
      # deterministic Faraday test adapter while keeping the production
      # middleware stack intact.
      def graph_connection(token: nil, api_url: 'https://graph.microsoft.com/v1.0', **_opts)
        token ||= 'integration-token'

        Faraday.new(url: api_url) do |conn|
          conn.request :json
          conn.use Legion::Extensions::MicrosoftTeams::Faraday::RetryAfter,
                   **retry_after_options, sleeper: @sleeper || ->(_) {}
          conn.response :json, content_type: /\bjson$/
          conn.headers['Authorization'] = "Bearer #{token}"
          conn.adapter :test, @stubs
        end
      end
    end
  end

  let(:host)  { host_class.new }
  let(:slept) { [] }

  before { host.sleeper = ->(s) { slept << s } }

  it 'raises Throttled carrying the last advertised retry_after after middleware exhausts retries' do
    stubs = Faraday::Adapter::Test::Stubs.new
    %w[5 7 11].each do |value|
      stubs.get('/me/chats') { [429, { 'Retry-After' => value }, { 'error' => 'throttled' }] }
    end
    host.stubs = stubs

    raised = nil
    begin
      host.send(:graph_get, '/me/chats', token: 'tok')
    rescue Legion::Extensions::MicrosoftTeams::Errors::Throttled => e
      raised = e
    end

    expect(raised).not_to be_nil
    expect(raised.status).to eq(429)
    expect(raised.attempts).to eq(2)
    # The *last* response advertised 11s — that's what an actor should
    # defer on, not the first or an average.
    expect(raised.retry_after).to eq(11.0)
    expect(raised.retry_after_known?).to be(true)
    expect(slept).to eq([5.0, 7.0])
  end

  it 'returns the parsed body unchanged when a single 429 is followed by 200' do
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get('/me/chats') { [429, { 'Retry-After' => '0' }, ''] }
    stubs.get('/me/chats') { [200, { 'Content-Type' => 'application/json' }, '{"value":[{"id":"chat-1"}]}'] }
    host.stubs = stubs

    result = host.send(:graph_get, '/me/chats', token: 'tok')

    expect(result['value']).to eq([{ 'id' => 'chat-1' }])
  end
end

# NOTE: actor-level integration — verifying that a poller catches Throttled
# and defers its NEXT scheduled run instead of re-firing on the standard
# interval — is intentionally out of scope for THIS PR. The follow-up
# (issue to be filed) will add that behavior to the actor base class plus
# the five existing pollers. When that lands, replace this comment with a
# spec that drives the actor through one tick, raises Throttled from the
# Graph call, and asserts the actor schedules its next run at
# `Time.now + retry_after` rather than `Time.now + POLL_INTERVAL`.
