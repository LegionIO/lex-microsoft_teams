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

require 'legion/extensions/microsoft_teams/actors/incremental_sync'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::IncrementalSync do
  let(:actor) { described_class.allocate }

  describe '#delay' do
    it 'returns 900 seconds by default' do
      expect(actor.delay).to eq(900)
    end
  end

  describe '#runner_function' do
    it 'calls incremental_sync' do
      expect(actor.runner_function).to eq('incremental_sync')
    end
  end

  describe '#run_now?' do
    it 'returns false' do
      expect(actor.run_now?).to be false
    end
  end

  describe '#generate_task?' do
    it 'returns false' do
      expect(actor.generate_task?).to be false
    end
  end
end
