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
  end

  it 'has a 2 second delay' do
    expect(actor.delay).to eq(2.0)
  end

  it 'does not generate tasks' do
    expect(actor.generate_task?).to be false
  end

  it 'does not check subtasks' do
    expect(actor.check_subtask?).to be false
  end

  describe '#manual' do
    before do
      allow(token_cache).to receive(:previously_authenticated?).and_return(false)
    end

    context 'when token loads and refreshes successfully' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return('valid-token')
      end

      it 'does not trigger browser auth' do
        expect(actor).not_to receive(:attempt_browser_reauth)
        actor.manual
      end
    end

    context 'when token loads but refresh fails and previously authenticated' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return(nil)
        allow(token_cache).to receive(:previously_authenticated?).and_return(true)
        allow(actor).to receive(:attempt_browser_reauth).and_return(true)
      end

      it 'triggers browser re-auth' do
        actor.manual
        expect(actor).to have_received(:attempt_browser_reauth)
      end
    end

    context 'when token loads but refresh fails and never authenticated' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return(nil)
        allow(token_cache).to receive(:previously_authenticated?).and_return(false)
        allow(actor).to receive(:auto_authenticate?).and_return(false)
      end

      it 'does not trigger browser re-auth' do
        expect(actor).not_to receive(:attempt_browser_reauth)
        actor.manual
      end
    end

    context 'when no token file exists' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(false)
        allow(token_cache).to receive(:previously_authenticated?).and_return(false)
        allow(actor).to receive(:auto_authenticate?).and_return(false)
      end

      it 'does nothing silently' do
        expect(actor).not_to receive(:attempt_browser_reauth)
        actor.manual
      end
    end

    context 'when no token exists and auto_authenticate is true' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(false)
        allow(token_cache).to receive(:previously_authenticated?).and_return(false)
        allow(actor).to receive(:auto_authenticate?).and_return(true)
        allow(actor).to receive(:attempt_browser_reauth).and_return(true)
      end

      it 'triggers browser auth for first-time user' do
        actor.manual
        expect(actor).to have_received(:attempt_browser_reauth)
      end
    end

    context 'when token loads but refresh fails, never authenticated, auto_authenticate true' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(true)
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

    context 'when no token loads but previously authenticated' do
      before do
        allow(token_cache).to receive(:load_from_vault).and_return(false)
        allow(token_cache).to receive(:previously_authenticated?).and_return(true)
        allow(actor).to receive(:attempt_browser_reauth).and_return(true)
      end

      it 'triggers browser re-auth' do
        actor.manual
        expect(actor).to have_received(:attempt_browser_reauth)
      end
    end
  end
end
