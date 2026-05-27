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

$LOADED_FEATURES << 'legion/extensions/actors/every'

require 'legion/extensions/microsoft_teams/actors/observed_chat_poller'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::ObservedChatPoller do
  subject(:actor) { described_class.allocate }

  it 'reads interval from settings' do
    allow(Legion::Settings).to receive(:dig)
      .with(:microsoft_teams, :observed_chat_poller, :interval).and_return(60)
    expect(actor.time).to eq(60)
  end

  it 'routes to observe_message' do
    expect(actor.runner_function).to eq('observe_message')
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

  it 'is disabled when settings say so' do
    allow(Legion::Settings).to receive(:dig)
      .with(:microsoft_teams, :observed_chat_poller, :enabled).and_return(false)
    expect(actor.enabled?).to be false
  end

  it 'exposes a subscription_registry' do
    expect(actor).to respond_to(:subscription_registry)
  end
end
