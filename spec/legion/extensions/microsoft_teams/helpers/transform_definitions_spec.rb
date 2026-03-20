# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::TransformDefinitions do
  describe '.conversation_extract' do
    let(:definition) { described_class.conversation_extract }

    it 'returns a hash with required keys' do
      expect(definition).to include(:name, :prompt, :schema, :structured)
    end

    it 'has structured output enabled' do
      expect(definition[:structured]).to be true
    end

    it 'schema includes style, topics, relationship, and action_items' do
      props = definition[:schema][:properties]
      expect(props.keys).to include(:communication_style, :topics, :relationship_context, :action_items)
    end

    it 'has the expected definition name' do
      expect(definition[:name]).to eq('teams.conversation.extract')
    end
  end

  describe '.person_summary' do
    let(:definition) { described_class.person_summary }

    it 'returns a definition for summarizing a person profile' do
      expect(definition[:name]).to eq('teams.person.summary')
      expect(definition[:structured]).to be true
    end
  end
end
