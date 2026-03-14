# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::AdaptiveCards do
  let(:runner) { Object.new.extend(described_class) }

  describe '#build_card' do
    it 'builds a valid adaptive card' do
      body = [{ type: 'TextBlock', text: 'Hello' }]
      result = runner.build_card(body: body)
      card = result[:result]

      expect(card['type']).to eq('AdaptiveCard')
      expect(card['version']).to eq('1.4')
      expect(card['body']).to eq(body)
    end

    it 'includes actions when provided' do
      body = [{ type: 'TextBlock', text: 'Test' }]
      actions = [{ type: 'Action.OpenUrl', title: 'Open', url: 'https://example.com' }]
      result = runner.build_card(body: body, actions: actions)

      expect(result[:result]['actions']).to eq(actions)
    end
  end

  describe '#text_block' do
    it 'builds a text block element' do
      result = runner.text_block(text: 'Hello World', size: 'large', weight: 'bolder')
      block = result[:result]

      expect(block[:type]).to eq('TextBlock')
      expect(block[:text]).to eq('Hello World')
      expect(block[:size]).to eq('large')
      expect(block[:weight]).to eq('bolder')
    end

    it 'omits default size and weight' do
      result = runner.text_block(text: 'Simple')
      block = result[:result]

      expect(block).not_to have_key(:size)
      expect(block).not_to have_key(:weight)
    end
  end

  describe '#fact_set' do
    it 'builds a fact set from a hash' do
      result = runner.fact_set(facts: { 'Status' => 'Active', 'Priority' => 'High' })
      facts = result[:result][:facts]

      expect(facts.length).to eq(2)
      expect(facts.first[:title]).to eq('Status')
      expect(facts.first[:value]).to eq('Active')
    end
  end

  describe '#message_attachment' do
    it 'wraps a card as a message attachment' do
      card = { 'type' => 'AdaptiveCard', 'body' => [] }
      result = runner.message_attachment(card: card)

      expect(result[:result][:contentType]).to eq('application/vnd.microsoft.card.adaptive')
      expect(result[:result][:content]).to eq(card)
    end
  end
end
