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

require 'legion/extensions/microsoft_teams/actors/direct_chat_poller'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::DirectChatPoller do
  subject(:actor) { described_class.allocate }

  it 'has a 5 second interval' do
    expect(actor.time).to eq(5)
  end

  it 'uses the Bot runner class' do
    expect(actor.runner_class).to eq(Legion::Extensions::MicrosoftTeams::Runners::Bot)
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

  it 'routes to handle_message' do
    expect(actor.runner_function).to eq('handle_message')
  end

  it 'exposes a token_cache' do
    expect(actor).to respond_to(:token_cache)
  end
end
