# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/microsoft_teams/helpers/client'
require 'legion/extensions/microsoft_teams/helpers/graph_client'
require 'legion/extensions/microsoft_teams/errors'

# Defensive 429/503/504 handling in handle_graph_response — fires when a
# caller used a Faraday connection without the RetryAfter middleware
# installed (custom tests, ad-hoc tooling). Normal traffic with the
# middleware never reaches this branch because the middleware itself
# raises Throttled on exhaustion.
RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::GraphClient do
  let(:host_class) do
    Class.new do
      include Legion::Extensions::MicrosoftTeams::Helpers::Client
      include Legion::Extensions::MicrosoftTeams::Helpers::GraphClient
    end
  end

  let(:host) { host_class.new }

  def fake_response(status:, headers: {}, body: nil)
    instance_double('Faraday::Response', status: status, body: body, headers: headers)
  end

  def call_handler(response, path)
    host.send(:handle_graph_response, response, path)
  end

  describe '#handle_graph_response' do
    it 'raises Throttled with parsed delta-seconds Retry-After on 429' do
      response = fake_response(status: 429, headers: { 'Retry-After' => '42' }, body: {})

      expect { call_handler(response, '/me/chats') }.to raise_error(
        an_instance_of(Legion::Extensions::MicrosoftTeams::Errors::Throttled)
          .and(having_attributes(status: 429, retry_after: 42.0, request: '/me/chats'))
      )
    end

    it 'raises Throttled with parsed HTTP-date Retry-After on 429' do
      future = Time.now.utc + 30
      response = fake_response(status: 429, headers: { 'Retry-After' => future.httpdate }, body: {})

      raised = nil
      begin
        call_handler(response, '/me/chats')
      rescue Legion::Extensions::MicrosoftTeams::Errors::Throttled => e
        raised = e
      end

      expect(raised).not_to be_nil
      expect(raised.status).to eq(429)
      expect(raised.retry_after).to be_within(2.0).of(30.0)
    end

    it 'raises Throttled with retry_after=nil when 429 lacks the header' do
      response = fake_response(status: 429, headers: {}, body: {})

      raised = nil
      begin
        call_handler(response, '/me/chats')
      rescue Legion::Extensions::MicrosoftTeams::Errors::Throttled => e
        raised = e
      end

      expect(raised.retry_after).to be_nil
      expect(raised.retry_after_known?).to be(false)
    end

    it 'also raises Throttled on 503 (transient backend) for symmetry with the middleware' do
      response = fake_response(status: 503, headers: { 'Retry-After' => '5' }, body: {})

      expect { call_handler(response, '/me/chats') }.to raise_error(
        Legion::Extensions::MicrosoftTeams::Errors::Throttled
      ) { |e| expect(e.status).to eq(503) }
    end

    it 'does not raise Throttled on 200' do
      response = fake_response(status: 200, headers: {}, body: { 'ok' => true })

      expect(call_handler(response, '/me/chats')).to eq({ 'ok' => true })
    end

    it 'raises generic GraphError for other 4xx statuses' do
      response = fake_response(status: 418, headers: {}, body: { 'error' => { 'message' => 'teapot' } })

      expect { call_handler(response, '/me/chats') }.to raise_error(
        Legion::Extensions::MicrosoftTeams::Helpers::GraphClient::GraphError, /418/
      )
    end
  end
end
