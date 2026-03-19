# frozen_string_literal: true

module Legion
  module Extensions
    module Actors
      class Subscription # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

$LOADED_FEATURES << 'legion/extensions/actors/subscription'

require_relative '../../../../../lib/legion/extensions/microsoft_teams/actors/message_processor'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::MessageProcessor do
  subject(:actor) { described_class.allocate }

  it 'uses the Bot runner class' do
    expect(actor.runner_class).to eq('Legion::Extensions::MicrosoftTeams::Runners::Bot')
  end

  it 'routes to handle_message by default' do
    expect(actor.runner_function).to eq('handle_message')
  end

  it 'does not generate tasks' do
    expect(actor.generate_task?).to be false
  end

  it 'does not check subtasks' do
    expect(actor.check_subtask?).to be false
  end
end
