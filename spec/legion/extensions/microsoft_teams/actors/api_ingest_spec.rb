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
require 'legion/extensions/microsoft_teams/actors/api_ingest'

RSpec.describe Legion::Extensions::MicrosoftTeams::Actor::ApiIngest do
  let(:actor) { described_class.allocate }

  describe '#delay' do
    context 'when AuthValidator is defined' do
      it 'returns AuthValidator delay plus 5 seconds' do
        auth_validator = Legion::Extensions::MicrosoftTeams::Actor::AuthValidator.allocate
        expect(actor.delay).to eq(auth_validator.delay.to_f + 5.0)
      end

      it 'fires after AuthValidator to ensure boot ordering' do
        auth_validator = Legion::Extensions::MicrosoftTeams::Actor::AuthValidator.allocate
        expect(actor.delay).to be > auth_validator.delay
      end
    end

    context 'when AuthValidator is unavailable' do
      before do
        hide_const('Legion::Extensions::MicrosoftTeams::Actor::AuthValidator')
      end

      it 'falls back to 95.0 seconds' do
        expect(actor.delay).to eq(95.0)
      end
    end
  end

  describe '#runner_function' do
    it 'returns ingest_api' do
      expect(actor.runner_function).to eq('ingest_api')
    end
  end

  describe '#run_now?' do
    it 'returns true' do
      expect(actor.run_now?).to be true
    end
  end

  describe '#generate_task?' do
    it 'returns false' do
      expect(actor.generate_task?).to be false
    end
  end

  describe '#check_subtask?' do
    it 'returns false' do
      expect(actor.check_subtask?).to be false
    end
  end
end
