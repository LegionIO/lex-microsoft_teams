# frozen_string_literal: true

require 'spec_helper'

# Stub PreferenceProfile if lex-mesh not loaded
unless defined?(Legion::Extensions::Mesh::Helpers::PreferenceProfile)
  module Legion
    module Extensions
      module Mesh
        module Helpers
          module PreferenceProfile
            module_function

            def resolve(**)
              { verbosity: :normal, tone: :professional, format: :structured,
                technical_depth: :moderate, personality: nil, custom: {},
                sources: [:defaults], resolved_at: Time.now }
            end

            def preference_instructions(profile:) # rubocop:disable Lint/UnusedMethodArgument
              nil
            end
          end
        end
      end
    end
  end
end

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::PromptResolver do
  let(:resolver) { Object.new.extend(described_class) }
  let(:base_settings) do
    {
      bot: {
        system_prompt: 'You are a helpful assistant.',
        direct:        { system_prompt: nil },
        observe:       {
          system_prompt: 'Extract action items. Return structured JSON.'
        }
      }
    }
  end

  before do
    allow(resolver).to receive(:teams_settings).and_return(base_settings)
    allow(resolver).to receive(:conversation_overrides).and_return(nil)
  end

  describe '#resolve_prompt' do
    it 'returns base prompt when mode has no override' do
      expect(resolver.resolve_prompt(mode: :direct, conversation_id: '19:abc'))
        .to eq('You are a helpful assistant.')
    end

    it 'returns mode prompt when set' do
      expect(resolver.resolve_prompt(mode: :observe, conversation_id: '19:abc'))
        .to eq('Extract action items. Return structured JSON.')
    end

    it 'appends per-conversation override' do
      allow(resolver).to receive(:conversation_overrides).and_return(
        { system_prompt_append: 'Be concise.' }
      )
      result = resolver.resolve_prompt(mode: :direct, conversation_id: '19:abc')
      expect(result).to include('You are a helpful assistant.')
      expect(result).to include('Be concise.')
    end
  end

  describe '#resolve_llm_config' do
    let(:base_settings) do
      {
        bot: {
          llm: { model: nil, intent: { capability: :moderate } }
        }
      }
    end

    it 'returns base LLM config when no overrides' do
      config = resolver.resolve_llm_config(mode: :direct, conversation_id: '19:abc')
      expect(config[:intent]).to eq({ capability: :moderate })
    end

    it 'merges per-conversation LLM overrides' do
      allow(resolver).to receive(:conversation_overrides).and_return(
        { llm: { model: 'claude-haiku-4-5-20251001' } }
      )
      config = resolver.resolve_llm_config(mode: :direct, conversation_id: '19:abc')
      expect(config[:model]).to eq('claude-haiku-4-5-20251001')
      expect(config[:intent]).to eq({ capability: :moderate })
    end
  end

  describe '#resolve_prompt with preferences' do
    it 'appends preference instructions when owner_id provided' do
      profile_mod = Legion::Extensions::Mesh::Helpers::PreferenceProfile
      allow(profile_mod).to receive(:resolve).and_return(
        { verbosity: :concise, tone: :formal, format: :structured, technical_depth: :moderate,
          sources: [:explicit], resolved_at: Time.now }
      )
      allow(profile_mod).to receive(:preference_instructions).and_return(
        'Keep responses brief and to the point. Use formal, professional language.'
      )

      prompt = resolver.resolve_prompt(mode: :direct, conversation_id: '19:abc', owner_id: 'user1')
      expect(prompt).to include('brief')
      expect(prompt).to include('formal')
    end

    it 'works without owner_id (backward compatible)' do
      prompt = resolver.resolve_prompt(mode: :direct, conversation_id: '19:abc')
      expect(prompt).to be_a(String)
    end

    it 'handles PreferenceProfile errors gracefully' do
      profile_mod = Legion::Extensions::Mesh::Helpers::PreferenceProfile
      allow(profile_mod).to receive(:resolve).and_raise(StandardError, 'boom')

      prompt = resolver.resolve_prompt(mode: :direct, conversation_id: '19:abc', owner_id: 'user1')
      expect(prompt).to be_a(String)
    end
  end
end
