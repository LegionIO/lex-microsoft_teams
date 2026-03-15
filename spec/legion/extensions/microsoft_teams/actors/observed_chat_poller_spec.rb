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

  it 'has a 30 second interval' do
    expect(actor.time).to eq(30)
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

  it 'is disabled when Legion::Settings is not defined' do
    expect(actor.enabled?).to be false
  end
end
