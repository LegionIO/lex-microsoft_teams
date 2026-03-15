# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::HighWaterMark do
  let(:helper) { Object.new.extend(described_class) }

  describe '#hwm_key' do
    it 'builds a namespaced cache key' do
      expect(helper.hwm_key(chat_id: '19:abc')).to eq('teams:hwm:19:abc')
    end
  end

  describe '#new_messages' do
    let(:messages) do
      [
        { id: '3', createdDateTime: '2026-03-15T14:03:00Z' },
        { id: '2', createdDateTime: '2026-03-15T14:02:00Z' },
        { id: '1', createdDateTime: '2026-03-15T14:01:00Z' }
      ]
    end

    context 'with no stored high-water mark' do
      it 'returns all messages' do
        expect(helper.new_messages(chat_id: '19:abc', messages: messages).length).to eq(3)
      end
    end

    context 'with a stored high-water mark' do
      before { helper.instance_variable_set(:@hwm_fallback, { 'teams:hwm:19:abc' => '2026-03-15T14:02:00Z' }) }

      it 'returns only messages newer than the mark' do
        result = helper.new_messages(chat_id: '19:abc', messages: messages)
        expect(result.length).to eq(1)
        expect(result.first[:id]).to eq('3')
      end
    end
  end

  describe '#update_hwm_from_messages' do
    it 'stores the latest timestamp' do
      messages = [
        { createdDateTime: '2026-03-15T14:01:00Z' },
        { createdDateTime: '2026-03-15T14:03:00Z' },
        { createdDateTime: '2026-03-15T14:02:00Z' }
      ]
      helper.update_hwm_from_messages(chat_id: '19:abc', messages: messages)
      expect(helper.get_hwm(chat_id: '19:abc')).to eq('2026-03-15T14:03:00Z')
    end

    it 'does nothing for empty messages' do
      helper.update_hwm_from_messages(chat_id: '19:abc', messages: [])
      expect(helper.get_hwm(chat_id: '19:abc')).to be_nil
    end
  end
end
