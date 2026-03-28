# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/microsoft_teams/helpers/graph_client'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::GraphClient do
  include described_class

  let(:token) { 'test-bearer-token' }

  describe '#graph_get' do
    it 'calls graph_connection and returns parsed response' do
      mock_conn = double('connection')
      mock_response = double('response', status: 200, body: { 'value' => [{ 'id' => '123' }] })
      allow(self).to receive(:graph_connection).with(token: token).and_return(mock_conn)
      allow(mock_conn).to receive(:get).with('/me/chats', {}).and_return(mock_response)

      result = graph_get('/me/chats', token: token)
      expect(result).to eq({ 'value' => [{ 'id' => '123' }] })
    end

    it 'raises GraphError on 401' do
      mock_conn     = double('connection')
      mock_response = double('response', status: 401, body: { 'error' => { 'message' => 'Unauthorized' } })
      allow(self).to receive(:graph_connection).with(token: token).and_return(mock_conn)
      allow(mock_conn).to receive(:get).and_return(mock_response)

      expect { graph_get('/me', token: token) }.to raise_error(
        Legion::Extensions::MicrosoftTeams::Helpers::GraphClient::GraphError
      )
    end
  end

  describe '#graph_paginate' do
    it 'follows nextLink to collect all pages' do
      page1 = { 'value' => [{ 'id' => '1' }], '@odata.nextLink' => 'https://graph.microsoft.com/v1.0/next' }
      page2 = { 'value' => [{ 'id' => '2' }] }

      call_count = 0
      allow(self).to receive(:graph_get) do
        call_count += 1
        call_count == 1 ? page1 : page2
      end

      results = graph_paginate('/me/messages', token: token)
      expect(results).to eq([{ 'id' => '1' }, { 'id' => '2' }])
    end

    it 'returns empty array when response has no value' do
      allow(self).to receive(:graph_get).and_return({})
      results = graph_paginate('/me/messages', token: token)
      expect(results).to eq([])
    end
  end

  describe '#graph_post' do
    it 'posts JSON and returns body' do
      mock_conn     = double('connection')
      mock_response = double('response', status: 201, body: { 'id' => 'new-123' })
      allow(self).to receive(:graph_connection).with(token: token).and_return(mock_conn)
      allow(mock_conn).to receive(:post).and_return(mock_response)

      result = graph_post('/me/messages', body: { text: 'hello' }, token: token)
      expect(result).to eq({ 'id' => 'new-123' })
    end
  end
end
