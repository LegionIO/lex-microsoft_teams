# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::SessionManager do
  let(:manager) { described_class.new }

  describe '#get_or_create' do
    it 'creates a new session entry for unknown conversation' do
      session = manager.get_or_create(conversation_id: '19:abc', owner_id: 'user1', mode: :direct)
      expect(session).to be_a(Hash)
      expect(session[:message_count]).to eq(0)
    end

    it 'returns existing session for known conversation' do
      manager.get_or_create(conversation_id: '19:abc', owner_id: 'user1', mode: :direct)
      session = manager.get_or_create(conversation_id: '19:abc', owner_id: 'user1', mode: :direct)
      expect(session[:message_count]).to eq(0)
    end
  end

  describe '#touch' do
    it 'increments message count' do
      manager.get_or_create(conversation_id: '19:abc', owner_id: 'user1', mode: :direct)
      manager.touch(conversation_id: '19:abc')
      session = manager.get_or_create(conversation_id: '19:abc', owner_id: 'user1', mode: :direct)
      expect(session[:message_count]).to eq(1)
    end
  end

  describe '#add_message' do
    it 'appends a message to the session' do
      manager.get_or_create(conversation_id: '19:abc', owner_id: 'user1', mode: :direct)
      manager.add_message(conversation_id: '19:abc', role: :user, content: 'hello')
      msgs = manager.recent_messages(conversation_id: '19:abc')
      expect(msgs.length).to eq(1)
      expect(msgs.first[:content]).to eq('hello')
    end
  end

  describe '#should_flush?' do
    it 'returns true when message count exceeds threshold' do
      manager.get_or_create(conversation_id: '19:abc', owner_id: 'user1', mode: :direct)
      21.times { manager.touch(conversation_id: '19:abc') }
      expect(manager.should_flush?(conversation_id: '19:abc')).to be true
    end

    it 'returns false when message count is below threshold' do
      manager.get_or_create(conversation_id: '19:abc', owner_id: 'user1', mode: :direct)
      expect(manager.should_flush?(conversation_id: '19:abc')).to be false
    end
  end

  describe '#flush_idle' do
    it 'removes sessions idle longer than timeout' do
      manager.get_or_create(conversation_id: '19:abc', owner_id: 'user1', mode: :direct)
      manager.instance_variable_get(:@sessions)['19:abc'][:last_active] = Time.now - 1000
      flushed = manager.flush_idle(timeout: 900)
      expect(flushed).to include('19:abc')
      expect(manager.active_sessions).to eq(0)
    end
  end

  describe '#shutdown' do
    it 'persists and clears all sessions' do
      manager.get_or_create(conversation_id: '19:abc', owner_id: 'user1', mode: :direct)
      manager.get_or_create(conversation_id: '19:xyz', owner_id: 'user2', mode: :direct)
      manager.shutdown
      expect(manager.active_sessions).to eq(0)
    end
  end
end
