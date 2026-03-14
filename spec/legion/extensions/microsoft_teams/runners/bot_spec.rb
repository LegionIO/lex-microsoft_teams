# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Bot do
  let(:runner) { Object.new.extend(described_class) }
  let(:bot_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:bot_connection).and_return(bot_conn)
  end

  describe '#send_activity' do
    it 'sends an activity to a conversation' do
      activity = { type: 'message', text: 'Hello from bot' }
      response = instance_double(Faraday::Response, body: { 'id' => 'a1' })
      allow(bot_conn).to receive(:post).with('/v3/conversations/conv1/activities', activity).and_return(response)

      result = runner.send_activity(service_url: 'https://smba.trafficmanager.net/teams/', conversation_id: 'conv1', activity: activity)
      expect(result[:result]['id']).to eq('a1')
    end
  end

  describe '#reply_to_activity' do
    it 'replies to an existing activity' do
      response = instance_double(Faraday::Response, body: { 'id' => 'a2' })
      allow(bot_conn).to receive(:post).with('/v3/conversations/conv1/activities/a1', anything).and_return(response)

      result = runner.reply_to_activity(
        service_url: 'https://smba.trafficmanager.net/teams/',
        conversation_id: 'conv1',
        activity_id: 'a1',
        text: 'Reply text'
      )
      expect(result[:result]['id']).to eq('a2')
    end
  end

  describe '#send_text' do
    it 'sends a simple text message' do
      response = instance_double(Faraday::Response, body: { 'id' => 'a3' })
      allow(bot_conn).to receive(:post).with('/v3/conversations/conv1/activities',
                                             { type: 'message', text: 'Simple text' }).and_return(response)

      result = runner.send_text(service_url: 'https://smba.trafficmanager.net/teams/', conversation_id: 'conv1', text: 'Simple text')
      expect(result[:result]['id']).to eq('a3')
    end
  end

  describe '#send_card' do
    it 'sends an adaptive card' do
      card = { 'type' => 'AdaptiveCard', 'body' => [{ 'type' => 'TextBlock', 'text' => 'Card' }] }
      response = instance_double(Faraday::Response, body: { 'id' => 'a4' })
      allow(bot_conn).to receive(:post).with('/v3/conversations/conv1/activities', anything).and_return(response)

      result = runner.send_card(service_url: 'https://smba.trafficmanager.net/teams/', conversation_id: 'conv1', card: card)
      expect(result[:result]['id']).to eq('a4')
    end
  end

  describe '#create_conversation' do
    it 'creates a new conversation with a user' do
      response = instance_double(Faraday::Response, body: { 'id' => 'conv2' })
      allow(bot_conn).to receive(:post).with('/v3/conversations', hash_including(
                                               bot: { id: 'bot-id' }
                                             )).and_return(response)

      result = runner.create_conversation(
        service_url: 'https://smba.trafficmanager.net/teams/',
        bot_id: 'bot-id',
        user_id: 'user-id'
      )
      expect(result[:result]['id']).to eq('conv2')
    end
  end

  describe '#get_conversation_members' do
    it 'lists conversation members' do
      response = instance_double(Faraday::Response, body: [{ 'id' => 'user-id', 'name' => 'User A' }])
      allow(bot_conn).to receive(:get).with('/v3/conversations/conv1/members').and_return(response)

      result = runner.get_conversation_members(service_url: 'https://smba.trafficmanager.net/teams/', conversation_id: 'conv1')
      expect(result[:result].first['name']).to eq('User A')
    end
  end
end
