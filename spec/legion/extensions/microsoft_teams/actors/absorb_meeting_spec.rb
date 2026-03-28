# frozen_string_literal: true

require 'spec_helper'

module Legion
  module Extensions
    module Actors
      class Subscription # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

$LOADED_FEATURES << 'legion/extensions/actors/subscription'

require 'legion/extensions/microsoft_teams/actors/absorb_meeting'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::AbsorbMeeting do
  subject(:actor) { described_class.allocate }

  it 'inherits from Subscription' do
    expect(described_class.superclass).to eq(Legion::Extensions::Actors::Subscription)
  end

  it 'routes to the Meeting absorber runner class' do
    expect(actor.runner_class).to eq('Legion::Extensions::MicrosoftTeams::Absorbers::Meeting')
  end

  it 'routes to the absorb function' do
    expect(actor.runner_function).to eq('absorb')
  end

  it 'does not generate tasks' do
    expect(actor.generate_task?).to be false
  end

  it 'does not check subtasks' do
    expect(actor.check_subtask?).to be false
  end
end
