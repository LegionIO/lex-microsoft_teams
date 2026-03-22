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

  describe '#manual' do
    it 'returns nil when no token is available' do
      allow(actor).to receive(:resolve_token).and_return(nil)
      expect(actor.manual).to be_nil
    end

    it 'calls incremental_sync on runner_class when token is present' do
      allow(actor).to receive(:resolve_token).and_return('test-token')
      runner = Legion::Extensions::MicrosoftTeams::Runners::ProfileIngest
      expect(runner).to receive(:incremental_sync).with(
        token: 'test-token', top_people: 10, message_depth: 50
      )
      actor.manual
    end
  end
end
