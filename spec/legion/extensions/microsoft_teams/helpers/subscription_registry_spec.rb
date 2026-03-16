# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::SubscriptionRegistry do
  subject(:registry) { described_class.new }

  describe '#subscribe' do
    it 'adds a new subscription' do
      registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
      subs = registry.list(owner_id: 'user1')
      expect(subs.length).to eq(1)
      expect(subs.first[:peer_name]).to eq('Sarah')
    end

    it 'sets enabled: true by default' do
      registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
      subs = registry.list(owner_id: 'user1')
      expect(subs.first[:enabled]).to be true
    end

    it 'does not duplicate existing subscription' do
      registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
      registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
      subs = registry.list(owner_id: 'user1')
      expect(subs.length).to eq(1)
    end
  end

  describe '#unsubscribe' do
    it 'removes a subscription' do
      registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
      registry.unsubscribe(owner_id: 'user1', chat_id: 'chat-1')
      expect(registry.list(owner_id: 'user1')).to be_empty
    end

    it 'ignores non-existent subscriptions' do
      expect { registry.unsubscribe(owner_id: 'user1', chat_id: 'nope') }.not_to raise_error
    end
  end

  describe '#list' do
    it 'returns only subscriptions for the given owner' do
      registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
      registry.subscribe(owner_id: 'user2', chat_id: 'chat-2', peer_name: 'Bob')
      expect(registry.list(owner_id: 'user1').length).to eq(1)
    end

    it 'returns empty array when no subscriptions exist' do
      expect(registry.list(owner_id: 'user1')).to eq([])
    end
  end

  describe '#pause' do
    it 'sets enabled to false' do
      registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
      registry.pause(owner_id: 'user1', chat_id: 'chat-1')
      subs = registry.list(owner_id: 'user1')
      expect(subs.first[:enabled]).to be false
    end
  end

  describe '#resume' do
    it 'sets enabled to true' do
      registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
      registry.pause(owner_id: 'user1', chat_id: 'chat-1')
      registry.resume(owner_id: 'user1', chat_id: 'chat-1')
      subs = registry.list(owner_id: 'user1')
      expect(subs.first[:enabled]).to be true
    end
  end

  describe '#active_subscriptions' do
    it 'returns only enabled subscriptions' do
      registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
      registry.subscribe(owner_id: 'user1', chat_id: 'chat-2', peer_name: 'Bob')
      registry.pause(owner_id: 'user1', chat_id: 'chat-2')
      expect(registry.active_subscriptions.length).to eq(1)
    end
  end

  describe '#find_by_peer_name' do
    it 'finds a subscription by case-insensitive peer name' do
      registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah Connor')
      result = registry.find_by_peer_name(owner_id: 'user1', peer_name: 'sarah connor')
      expect(result).not_to be_nil
      expect(result[:chat_id]).to eq('chat-1')
    end

    it 'returns nil when not found' do
      expect(registry.find_by_peer_name(owner_id: 'user1', peer_name: 'Nobody')).to be_nil
    end
  end
end
