# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::TokenCache do
  subject(:cache) { described_class.new }

  let(:tmp_token_path) { "/tmp/token_cache_spec_#{::Process.pid}.json" } # rubocop:disable Style/RedundantConstantBase

  before do
    allow(cache).to receive(:local_token_path).and_return(tmp_token_path)
  end

  after { FileUtils.rm_f(tmp_token_path) }

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

  describe '#cached_delegated_token' do
    it 'returns nil when no delegated token is cached' do
      expect(cache.cached_delegated_token).to be_nil
    end

    it 'returns the cached delegated token' do
      cache.store_delegated_token(
        access_token:  'delegated-token-123',
        refresh_token: 'refresh-123',
        expires_in:    3600,
        scopes:        'OnlineMeetings.Read'
      )
      expect(cache.cached_delegated_token).to eq('delegated-token-123')
    end

    it 'returns nil when the delegated token is expired and refresh fails' do
      cache.store_delegated_token(
        access_token:  'old-token',
        refresh_token: 'refresh-123',
        expires_in:    -1,
        scopes:        'OnlineMeetings.Read'
      )
      expect(cache.cached_delegated_token).to be_nil
    end
  end

  describe '#store_delegated_token' do
    it 'stores token data in memory' do
      cache.store_delegated_token(
        access_token:  'token-abc',
        refresh_token: 'refresh-abc',
        expires_in:    3600,
        scopes:        'scope1'
      )
      expect(cache.cached_delegated_token).to eq('token-abc')
    end
  end

  describe '#clear_delegated_token!' do
    it 'clears the delegated token cache' do
      cache.store_delegated_token(
        access_token:  'token-abc',
        refresh_token: 'refresh-abc',
        expires_in:    3600,
        scopes:        'scope1'
      )
      cache.clear_delegated_token!
      expect(cache.cached_delegated_token).to be_nil
    end
  end

  describe '#load_from_vault' do
    it 'falls back to local when Legion::Crypt is not defined' do
      expect(cache.load_from_vault).to be false
    end
  end

  describe '#save_to_vault' do
    it 'saves to local file when Legion::Crypt is not defined' do
      cache.store_delegated_token(
        access_token:  'token-abc',
        refresh_token: 'refresh-abc',
        expires_in:    3600,
        scopes:        'scope1'
      )
      expect(cache.save_to_vault).to be false
      expect(File.exist?(cache.send(:local_token_path))).to be true
    end

    it 'returns false when no delegated token is stored' do
      expect(cache.save_to_vault).to be false
    end
  end

  describe '#save_to_local / #load_from_local' do
    it 'round-trips token data through a local file' do
      cache.store_delegated_token(
        access_token:  'local-token',
        refresh_token: 'local-refresh',
        expires_in:    3600,
        scopes:        'OnlineMeetings.Read'
      )
      cache.save_to_local

      new_cache = described_class.new
      allow(new_cache).to receive(:local_token_path).and_return(cache.send(:local_token_path))
      expect(new_cache.load_from_local).to be true
      expect(new_cache.cached_delegated_token).to eq('local-token')
    end

    it 'sets file permissions to 0600' do
      cache.store_delegated_token(
        access_token:  'token',
        refresh_token: 'refresh',
        expires_in:    3600,
        scopes:        'scope1'
      )
      cache.save_to_local
      mode = File.stat(cache.send(:local_token_path)).mode & 0o777
      expect(mode).to eq(0o600)
    end

    it 'returns false when no local file exists' do
      expect(cache.load_from_local).to be false
    end
  end

  describe '#authenticated?' do
    it 'returns false when no delegated token is cached' do
      expect(cache.authenticated?).to be false
    end

    it 'returns true when a delegated token is stored' do
      cache.store_delegated_token(
        access_token: 'tok', refresh_token: 'ref',
        expires_in: 3600, scopes: 'scope1'
      )
      expect(cache.authenticated?).to be true
    end

    it 'returns false after clearing delegated token' do
      cache.store_delegated_token(
        access_token: 'tok', refresh_token: 'ref',
        expires_in: 3600, scopes: 'scope1'
      )
      cache.clear_delegated_token!
      expect(cache.authenticated?).to be false
    end
  end

  describe '#previously_authenticated?' do
    it 'returns false when no local file exists' do
      expect(cache.previously_authenticated?).to be false
    end

    it 'returns true after save_to_local' do
      cache.store_delegated_token(
        access_token: 'tok', refresh_token: 'ref',
        expires_in: 3600, scopes: 'scope1'
      )
      cache.save_to_local
      expect(cache.previously_authenticated?).to be true
    end
  end

  describe '#vault_path' do
    it 'returns the default path with users/ prefix' do
      allow(cache).to receive(:teams_auth_settings).and_return({ delegated: {} })
      user = ENV.fetch('USER', 'default')
      expect(cache.send(:vault_path)).to eq("users/#{user}/microsoft_teams/delegated_token")
    end

    it 'returns a custom vault_path when configured' do
      allow(cache).to receive(:teams_auth_settings).and_return(
        { delegated: { vault_path: 'custom/path/token' } }
      )
      expect(cache.send(:vault_path)).to eq('custom/path/token')
    end

    it 'falls back to default path when delegated settings are absent' do
      allow(cache).to receive(:teams_auth_settings).and_return({})
      user = ENV.fetch('USER', 'default')
      expect(cache.send(:vault_path)).to eq("users/#{user}/microsoft_teams/delegated_token")
    end
  end
end
