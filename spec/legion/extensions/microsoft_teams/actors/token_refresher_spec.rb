# frozen_string_literal: true

require 'spec_helper'

unless defined?(Legion::Extensions::Actors::Every)
  module Legion
    module Extensions
      module Actors
        class Every; end # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

$LOADED_FEATURES << 'legion/extensions/actors/every' unless $LOADED_FEATURES.include?('legion/extensions/actors/every')

require 'legion/extensions/microsoft_teams/actors/token_refresher'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::TokenRefresher do
  subject(:actor) { described_class.allocate }

  let(:token_cache) { instance_double(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache) }

  before do
    allow(actor).to receive(:token_cache).and_return(token_cache)
  end

  it 'has a default 900 second interval' do
    expect(actor.time).to eq(900)
  end

  it 'does not run immediately on start' do
    expect(actor.run_now?).to be false
  end

  it 'does not generate tasks' do
    expect(actor.generate_task?).to be false
  end

  it 'does not check subtasks' do
    expect(actor.check_subtask?).to be false
  end

  describe '#manual' do
    context 'when not authenticated' do
      before do
        allow(token_cache).to receive(:authenticated?).and_return(false)
      end

      it 'skips refresh entirely' do
        expect(token_cache).not_to receive(:cached_delegated_token)
        actor.manual
      end
    end

    context 'when authenticated and refresh succeeds' do
      before do
        allow(token_cache).to receive(:authenticated?).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return('refreshed-token')
        allow(token_cache).to receive(:save_to_vault)
      end

      it 'saves the refreshed token' do
        actor.manual
        expect(token_cache).to have_received(:save_to_vault)
      end
    end

    context 'when authenticated but refresh fails and previously authenticated' do
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

    context 'when authenticated but refresh fails and never previously authenticated' do
      before do
        allow(token_cache).to receive(:authenticated?).and_return(true)
        allow(token_cache).to receive(:cached_delegated_token).and_return(nil)
        allow(token_cache).to receive(:previously_authenticated?).and_return(false)
      end

      it 'does not trigger browser re-auth' do
        expect(actor).not_to receive(:attempt_browser_reauth)
        actor.manual
      end
    end
  end
end
