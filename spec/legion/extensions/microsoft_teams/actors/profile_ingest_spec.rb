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

require 'legion/extensions/microsoft_teams/actors/profile_ingest'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::ProfileIngest do
  let(:actor) { described_class.allocate }

  describe '#delay' do
    it 'returns 5 seconds' do
      expect(actor.delay).to eq(5.0)
    end
  end

  describe '#runner_function' do
    it 'returns full_ingest' do
      expect(actor.runner_function).to eq('full_ingest')
    end
  end

  describe '#generate_task?' do
    it 'returns false' do
      expect(actor.generate_task?).to be false
    end
  end
end
