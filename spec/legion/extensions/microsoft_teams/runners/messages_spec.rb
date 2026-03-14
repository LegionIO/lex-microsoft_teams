# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Messages do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_chat_messages' do
    it 'lists messages in a chat' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'm1', 'body' => { 'content' => 'Hello' } }] })
      allow(graph_conn).to receive(:get).with('/chats/c1/messages', { '$top' => 50 }).and_return(response)

      result = runner.list_chat_messages(chat_id: 'c1')
      expect(result[:result]['value'].first['body']['content']).to eq('Hello')
    end
  end

  describe '#get_chat_message' do
    it 'retrieves a specific message' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm1' })
      allow(graph_conn).to receive(:get).with('/chats/c1/messages/m1').and_return(response)

      result = runner.get_chat_message(chat_id: 'c1', message_id: 'm1')
      expect(result[:result]['id']).to eq('m1')
    end
  end

  describe '#send_chat_message' do
    it 'sends a text message to a chat' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm2' })
      allow(graph_conn).to receive(:post).with('/chats/c1/messages', hash_including(
                                                                       body: { contentType: 'text', content: 'Hi there' }
                                                                     )).and_return(response)

      result = runner.send_chat_message(chat_id: 'c1', content: 'Hi there')
      expect(result[:result]['id']).to eq('m2')
    end
  end

  describe '#reply_to_chat_message' do
    it 'replies to a specific message' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm3' })
      allow(graph_conn).to receive(:post).with('/chats/c1/messages/m1/replies', anything).and_return(response)

      result = runner.reply_to_chat_message(chat_id: 'c1', message_id: 'm1', content: 'Reply text')
      expect(result[:result]['id']).to eq('m3')
    end
  end
end
