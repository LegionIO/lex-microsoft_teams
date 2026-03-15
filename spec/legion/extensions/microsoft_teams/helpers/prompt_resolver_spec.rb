# frozen_string_literal: true

require 'spec_helper'

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
end
