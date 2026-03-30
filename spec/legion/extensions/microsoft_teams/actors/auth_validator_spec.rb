# frozen_string_literal: true

require 'spec_helper'

unless defined?(Legion::Extensions::Actors::Once)
  module Legion
    module Extensions
      module Actors
        class Once; end # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

$LOADED_FEATURES << 'legion/extensions/actors/once' unless $LOADED_FEATURES.include?('legion/extensions/actors/once')

require 'legion/extensions/microsoft_teams/actors/auth_validator'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::AuthValidator do
  subject(:actor) { described_class.allocate }

  let(:token_cache) { instance_double(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache) }

  before do
    allow(actor).to receive(:token_cache).and_return(token_cache)
    allow(token_cache).to receive(:authenticated?).and_return(false)
    allow(token_cache).to receive(:previously_authenticated?).and_return(false)
    allow(token_cache).to receive(:cached_delegated_token).and_return(nil)
  end

  it 'has a 90 second delay' do
    expect(actor.delay).to eq(90.0)
  end

  it 'does not generate tasks' do
    expect(actor.generate_task?).to be false
  end

  it 'does not check subtasks' do
    expect(actor.check_subtask?).to be false
  end

  describe '#manual' do
    context 'when authenticated and token valid' do
      before do
        allow(token_cache).to receive(:authenticated?).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return('valid-token')
      end

      it 'does not trigger browser auth' do
        expect(actor).not_to receive(:attempt_browser_reauth)
        actor.manual
      end
    end

    context 'when authenticated but token expired and previously authenticated' do
      before do
        allow(token_cache).to receive(:authenticated?).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return(nil)
        allow(token_cache).to receive(:previously_authenticated?).and_return(true)
        allow(actor).to receive(:attempt_browser_reauth).and_return(true)
      end

      it 'triggers browser re-auth' do
        actor.manual
        expect(actor).to have_received(:attempt_browser_reauth)
      end
    end

    context 'when authenticated but token expired and never authenticated' do
      before do
        allow(token_cache).to receive(:authenticated?).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return(nil)
        allow(token_cache).to receive(:previously_authenticated?).and_return(false)
        allow(actor).to receive(:auto_authenticate?).and_return(false)
      end

      it 'does not trigger browser re-auth' do
        expect(actor).not_to receive(:attempt_browser_reauth)
        actor.manual
      end
    end

    context 'when not authenticated and no token file exists' do
      before do
        allow(actor).to receive(:auto_authenticate?).and_return(false)
      end

      it 'does nothing silently' do
        expect(actor).not_to receive(:attempt_browser_reauth)
        actor.manual
      end
    end

    context 'when not authenticated and auto_authenticate is true' do
      before do
        allow(actor).to receive(:auto_authenticate?).and_return(true)
        allow(actor).to receive(:attempt_browser_reauth).and_return(true)
      end

      it 'triggers browser auth for first-time user' do
        actor.manual
        expect(actor).to have_received(:attempt_browser_reauth)
      end
    end

    context 'when not authenticated but previously authenticated' do
      before do
        allow(token_cache).to receive(:previously_authenticated?).and_return(true)
        allow(actor).to receive(:attempt_browser_reauth).and_return(true)
      end

      it 'triggers browser re-auth' do
        actor.manual
        expect(actor).to have_received(:attempt_browser_reauth)
      end
    end

    context 'when authenticated, token expired, never authenticated, auto_authenticate true' do
      before do
        allow(token_cache).to receive(:authenticated?).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return(nil)
        allow(token_cache).to receive(:previously_authenticated?).and_return(false)
        allow(actor).to receive(:auto_authenticate?).and_return(true)
        allow(actor).to receive(:attempt_browser_reauth).and_return(true)
      end

      it 'triggers browser auth' do
        actor.manual
        expect(actor).to have_received(:attempt_browser_reauth)
      end
    end
  end

  describe '#teams_auth_settings' do
    context 'when Legion::Settings is not defined' do
      before do
        hide_const('Legion::Settings') if defined?(Legion::Settings)
        allow(ENV).to receive(:fetch).with('AZURE_TENANT_ID', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('AZURE_CLIENT_ID', nil).and_return(nil)
      end

      it 'returns a hash with nil tenant_id and client_id from ENV fallback' do
        result = actor.send(:teams_auth_settings)
        expect(result[:tenant_id]).to be_nil
        expect(result[:client_id]).to be_nil
      end
    end

    context 'when only auth sub-hash is present' do
      before do
        stub_const('Legion::Settings', { microsoft_teams: { auth: { tenant_id: 'auth-tenant', client_id: 'auth-client' } } })
        allow(Legion::Settings).to receive(:[]).with(:microsoft_teams).and_return(
          Legion::Settings[:microsoft_teams]
        )
      end

      it 'uses values from the auth sub-hash' do
        result = actor.send(:teams_auth_settings)
        expect(result[:tenant_id]).to eq('auth-tenant')
        expect(result[:client_id]).to eq('auth-client')
      end
    end

    context 'when top-level microsoft_teams keys are present but auth sub-hash is missing them' do
      before do
        stub_const('Legion::Settings', {})
        allow(Legion::Settings).to receive(:[]).with(:microsoft_teams).and_return(
          { tenant_id: 'top-tenant', client_id: 'top-client' }
        )
      end

      it 'falls back to top-level tenant_id and client_id' do
        result = actor.send(:teams_auth_settings)
        expect(result[:tenant_id]).to eq('top-tenant')
        expect(result[:client_id]).to eq('top-client')
      end
    end

    context 'when no settings are present but ENV vars are set' do
      before do
        stub_const('Legion::Settings', {})
        allow(Legion::Settings).to receive(:[]).with(:microsoft_teams).and_return(nil)
        allow(ENV).to receive(:fetch).with('AZURE_TENANT_ID', nil).and_return('env-tenant')
        allow(ENV).to receive(:fetch).with('AZURE_CLIENT_ID', nil).and_return('env-client')
      end

      it 'falls back to AZURE_TENANT_ID and AZURE_CLIENT_ID env vars' do
        result = actor.send(:teams_auth_settings)
        expect(result[:tenant_id]).to eq('env-tenant')
        expect(result[:client_id]).to eq('env-client')
      end
    end

    context 'when auth sub-hash has values and top-level also has values' do
      before do
        stub_const('Legion::Settings', {})
        allow(Legion::Settings).to receive(:[]).with(:microsoft_teams).and_return(
          { auth: { tenant_id: 'auth-tenant', client_id: 'auth-client' }, tenant_id: 'top-tenant', client_id: 'top-client' }
        )
      end

      it 'prefers auth sub-hash values over top-level values' do
        result = actor.send(:teams_auth_settings)
        expect(result[:tenant_id]).to eq('auth-tenant')
        expect(result[:client_id]).to eq('auth-client')
      end
    end
  end
end
