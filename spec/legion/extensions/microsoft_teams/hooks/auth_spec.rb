# frozen_string_literal: true

require 'spec_helper'

unless defined?(Legion::Extensions::Hooks::Base)
  module Legion
    module Extensions
      module Hooks
        class Base
          class << self
            def mount(path)
              @mount_path = path
            end

            attr_reader :mount_path, :route_type, :verify_type
          end

          def route(_headers, _payload)
            :handle
          end

          def verify(_headers, _body)
            true
          end
        end
      end

      module Helpers
        module Lex; end
      end
    end
  end
end

$LOADED_FEATURES << 'legion/extensions/hooks/base' unless $LOADED_FEATURES.any? { |f| f.end_with?('hooks/base.rb') }

require 'legion/extensions/microsoft_teams/hooks/auth'

RSpec.describe Legion::Extensions::MicrosoftTeams::Hooks::Auth do
  describe '.mount_path' do
    it 'declares /callback mount path' do
      expect(described_class.mount_path).to eq('/callback')
    end
  end

  describe '#route' do
    it 'always routes to auth_callback' do
      hook = described_class.new
      expect(hook.route({}, {})).to eq(:auth_callback)
    end
  end

  describe '#runner_class' do
    it 'returns the Auth runner class name' do
      hook = described_class.new
      expect(hook.runner_class).to eq('Legion::Extensions::MicrosoftTeams::Runners::Auth')
    end
  end

  describe '#verify' do
    it 'allows all requests (no verification configured)' do
      hook = described_class.new
      expect(hook.verify({}, '')).to be true
    end
  end
end
