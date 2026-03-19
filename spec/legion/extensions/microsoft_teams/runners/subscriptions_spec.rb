# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Subscriptions do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_subscriptions' do
    it 'lists all subscriptions' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 's1' }] })
      allow(graph_conn).to receive(:get).with('subscriptions').and_return(response)

      result = runner.list_subscriptions
      expect(result[:result]['value'].first['id']).to eq('s1')
    end
  end

  describe '#create_subscription' do
    it 'creates a change notification subscription' do
      response = instance_double(Faraday::Response, body: { 'id' => 's2', 'resource' => '/chats/c1/messages' })
      allow(graph_conn).to receive(:post).with('subscriptions', hash_including(
                                                                  changeType: 'created',
                                                                  resource:   '/chats/c1/messages'
                                                                )).and_return(response)

      result = runner.create_subscription(
        resource:         '/chats/c1/messages',
        change_type:      'created',
        notification_url: 'https://example.com/webhook',
        expiration:       '2026-03-15T00:00:00Z'
      )
      expect(result[:result]['id']).to eq('s2')
    end
  end

  describe '#renew_subscription' do
    it 'extends the expiration' do
      response = instance_double(Faraday::Response, body: { 'id' => 's1', 'expirationDateTime' => '2026-03-16T00:00:00Z' })
      allow(graph_conn).to receive(:patch).with('subscriptions/s1', anything).and_return(response)

      result = runner.renew_subscription(subscription_id: 's1', expiration: '2026-03-16T00:00:00Z')
      expect(result[:result]['expirationDateTime']).to eq('2026-03-16T00:00:00Z')
    end
  end

  describe '#delete_subscription' do
    it 'deletes a subscription' do
      response = instance_double(Faraday::Response, body: '')
      allow(graph_conn).to receive(:delete).with('subscriptions/s1').and_return(response)

      result = runner.delete_subscription(subscription_id: 's1')
      expect(result[:result]).to eq('')
    end
  end

  describe '#subscribe_to_chat_messages' do
    it 'creates a subscription for chat messages' do
      response = instance_double(Faraday::Response, body: { 'id' => 's3', 'resource' => '/chats/c1/messages' })
      allow(graph_conn).to receive(:post).with('subscriptions', hash_including(
                                                                  resource: '/chats/c1/messages'
                                                                )).and_return(response)

      result = runner.subscribe_to_chat_messages(
        chat_id:          'c1',
        notification_url: 'https://example.com/webhook',
        expiration:       '2026-03-15T00:00:00Z'
      )
      expect(result[:result]['resource']).to eq('/chats/c1/messages')
    end
  end
end
