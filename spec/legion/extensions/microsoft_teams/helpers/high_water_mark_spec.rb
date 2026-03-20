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

  describe '#get_extended_hwm' do
    it 'returns nil for unknown chat' do
      expect(helper.get_extended_hwm(chat_id: 'chat-1')).to be_nil
    end

    it 'returns the stored extended hwm hash' do
      helper.set_extended_hwm(chat_id: 'chat-1', last_message_at: '2026-03-20T15:00:00Z',
                              last_ingested_at: '2026-03-20T14:55:00Z', message_count: 10)
      result = helper.get_extended_hwm(chat_id: 'chat-1')
      expect(result[:last_message_at]).to eq('2026-03-20T15:00:00Z')
      expect(result[:last_ingested_at]).to eq('2026-03-20T14:55:00Z')
      expect(result[:message_count]).to eq(10)
    end
  end

  describe '#update_extended_hwm' do
    it 'updates last_message_at and increments message_count' do
      helper.set_extended_hwm(chat_id: 'chat-1', last_message_at: '2026-03-20T14:00:00Z',
                              last_ingested_at: '2026-03-20T14:00:00Z', message_count: 5)
      helper.update_extended_hwm(chat_id: 'chat-1', last_message_at: '2026-03-20T15:00:00Z',
                                 new_message_count: 3)
      result = helper.get_extended_hwm(chat_id: 'chat-1')
      expect(result[:last_message_at]).to eq('2026-03-20T15:00:00Z')
      expect(result[:message_count]).to eq(8)
    end

    it 'updates last_ingested_at when ingested flag is true' do
      helper.set_extended_hwm(chat_id: 'chat-1', last_message_at: '2026-03-20T14:00:00Z',
                              last_ingested_at: '2026-03-20T13:00:00Z', message_count: 5)
      helper.update_extended_hwm(chat_id: 'chat-1', last_message_at: '2026-03-20T15:00:00Z',
                                 new_message_count: 3, ingested: true)
      result = helper.get_extended_hwm(chat_id: 'chat-1')
      expect(result[:last_ingested_at]).not_to eq('2026-03-20T13:00:00Z')
    end
  end

  describe '#persist_hwm_as_trace' do
    it 'calls store_trace with procedural type and hwm tags' do
      memory_runner = double('memory_runner')
      allow(helper).to receive(:memory_runner).and_return(memory_runner)
      expect(memory_runner).to receive(:store_trace).with(hash_including(
                                                            type:        :procedural,
                                                            domain_tags: ['teams', 'hwm', 'chat:chat-1']
                                                          ))
      helper.set_extended_hwm(chat_id: 'chat-1', last_message_at: '2026-03-20T15:00:00Z',
                              last_ingested_at: '2026-03-20T15:00:00Z', message_count: 10)
      helper.persist_hwm_as_trace(chat_id: 'chat-1')
    end
  end

  describe '#restore_hwm_from_traces' do
    it 'populates extended hwm from procedural traces' do
      memory_runner = double('memory_runner')
      allow(helper).to receive(:memory_runner).and_return(memory_runner)
      payload = '{"chat_id":"chat-1","last_message_at":"2026-03-20T15:00:00Z",' \
                '"last_ingested_at":"2026-03-20T14:55:00Z","message_count":10}'
      allow(memory_runner).to receive(:retrieve_by_domain).with(
        hash_including(domain_tag: 'teams')
      ).and_return([
                     { content_payload: payload,
                       domain_tags: %w[teams hwm chat:chat-1], trace_type: :procedural }
                   ])
      helper.restore_hwm_from_traces
      result = helper.get_extended_hwm(chat_id: 'chat-1')
      expect(result[:last_message_at]).to eq('2026-03-20T15:00:00Z')
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
