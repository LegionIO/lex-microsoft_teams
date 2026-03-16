# frozen_string_literal: true

require 'spec_helper'
require 'net/http'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::CallbackServer do
  describe '#start and #wait_for_callback' do
    it 'returns the port it is listening on' do
      server = described_class.new
      server.start
      expect(server.port).to be_a(Integer)
      expect(server.port).to be > 0
      server.shutdown
    end

    it 'captures code and state from the callback request' do
      server = described_class.new
      server.start

      Thread.new do
        sleep(0.1)
        Net::HTTP.get(URI("http://127.0.0.1:#{server.port}/callback?code=AUTH_CODE_123&state=STATE_ABC"))
      end

      result = server.wait_for_callback(timeout: 5)
      expect(result[:code]).to eq('AUTH_CODE_123')
      expect(result[:state]).to eq('STATE_ABC')
      server.shutdown
    end

    it 'returns nil on timeout' do
      server = described_class.new
      server.start
      result = server.wait_for_callback(timeout: 1)
      expect(result).to be_nil
      server.shutdown
    end
  end

  describe '#redirect_uri' do
    it 'returns the localhost callback URL with port' do
      server = described_class.new
      server.start
      expect(server.redirect_uri).to eq("http://localhost:#{server.port}/callback")
      server.shutdown
    end
  end
end
