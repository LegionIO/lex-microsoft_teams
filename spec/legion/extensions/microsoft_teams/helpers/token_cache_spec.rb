# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::TokenCache do
  subject(:cache) { described_class.new }

  describe '#cached_graph_token' do
    let(:auth_result) do
      { result: { 'access_token' => 'tok-abc', 'expires_in' => 3600 } }
    end

    before do
      allow(cache).to receive(:acquire_fresh_token).and_return(auth_result)
    end

    it 'acquires a fresh token on first call' do
      expect(cache.cached_graph_token).to eq('tok-abc')
      expect(cache).to have_received(:acquire_fresh_token).once
    end

    it 'returns cached token on subsequent calls' do
      cache.cached_graph_token
      cache.cached_graph_token
      expect(cache).to have_received(:acquire_fresh_token).once
    end

    it 'refreshes when token is expired' do
      cache.cached_graph_token
      cache.instance_variable_set(:@token_cache, {
                                    token: 'tok-old', expires_at: Time.now - 10
                                  })
      expect(cache.cached_graph_token).to eq('tok-abc')
      expect(cache).to have_received(:acquire_fresh_token).twice
    end

    it 'refreshes 60 seconds before expiry' do
      cache.cached_graph_token
      cache.instance_variable_set(:@token_cache, {
                                    token: 'tok-old', expires_at: Time.now + 30
                                  })
      expect(cache.cached_graph_token).to eq('tok-abc')
      expect(cache).to have_received(:acquire_fresh_token).twice
    end

    it 'does not refresh when token has plenty of time left' do
      cache.cached_graph_token
      cache.instance_variable_set(:@token_cache, {
                                    token: 'tok-fresh', expires_at: Time.now + 600
                                  })
      expect(cache.cached_graph_token).to eq('tok-fresh')
      expect(cache).to have_received(:acquire_fresh_token).once
    end

    it 'returns nil when acquire_fresh_token returns nil' do
      allow(cache).to receive(:acquire_fresh_token).and_return(nil)
      expect(cache.cached_graph_token).to be_nil
    end

    it 'returns nil when acquire_fresh_token raises' do
      allow(cache).to receive(:acquire_fresh_token).and_raise(StandardError, 'network error')
      expect(cache.cached_graph_token).to be_nil
    end
  end

  describe '#clear_token_cache!' do
    it 'forces next call to re-acquire' do
      allow(cache).to receive(:acquire_fresh_token).and_return(
        { result: { 'access_token' => 'tok-1', 'expires_in' => 3600 } }
      )
      cache.cached_graph_token
      cache.clear_token_cache!
      cache.cached_graph_token
      expect(cache).to have_received(:acquire_fresh_token).twice
    end
  end
end
