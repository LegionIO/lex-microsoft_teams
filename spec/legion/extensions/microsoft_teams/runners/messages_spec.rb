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
      allow(graph_conn).to receive(:get).with('chats/c1/messages', { '$top' => 50 }).and_return(response)

      result = runner.list_chat_messages(chat_id: 'c1')
      expect(result[:result]['value'].first['body']['content']).to eq('Hello')
    end

    it 'paginates across multiple pages when max_pages > 1' do
      page1_body = { '@odata.context'  => 'ctx',
                     'value'           => [{ 'id' => 'm1' }],
                     '@odata.nextLink' => 'https://graph.microsoft.com/v1.0/chats/c1/messages?$skip=50' }
      page2_body = { 'value'           => [{ 'id' => 'm2' }],
                     '@odata.nextLink' => 'https://graph.microsoft.com/v1.0/chats/c1/messages?$skip=100' }
      page3_body = { 'value' => [{ 'id' => 'm3' }] }

      page1_resp = instance_double(Faraday::Response, body: page1_body)
      page2_resp = instance_double(Faraday::Response, body: page2_body)
      page3_resp = instance_double(Faraday::Response, body: page3_body)

      allow(graph_conn).to receive(:get).with('chats/c1/messages', { '$top' => 50 }).and_return(page1_resp)
      allow(graph_conn).to receive(:get).with('https://graph.microsoft.com/v1.0/chats/c1/messages?$skip=50').and_return(page2_resp)
      allow(graph_conn).to receive(:get).with('https://graph.microsoft.com/v1.0/chats/c1/messages?$skip=100').and_return(page3_resp)

      result = runner.list_chat_messages(chat_id: 'c1', max_pages: 3)
      expect(result[:result]['value'].map { |m| m['id'] }).to eq(%w[m1 m2 m3])
      expect(result[:result]).not_to have_key('@odata.nextLink')
    end

    it 'caps per_page at 50 even if top is higher' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'm1' }] })
      allow(graph_conn).to receive(:get).with('chats/c1/messages', { '$top' => 50 }).and_return(response)

      runner.list_chat_messages(chat_id: 'c1', top: 200)
      expect(graph_conn).to have_received(:get).with('chats/c1/messages', { '$top' => 50 })
    end

    it 'stops paginating when no nextLink is returned' do
      page1_body = { '@odata.context' => 'ctx', 'value' => [{ 'id' => 'm1' }] }
      page1_resp = instance_double(Faraday::Response, body: page1_body)
      allow(graph_conn).to receive(:get).with('chats/c1/messages', { '$top' => 50 }).and_return(page1_resp)

      result = runner.list_chat_messages(chat_id: 'c1', max_pages: 5)
      expect(result[:result]['value'].size).to eq(1)
    end
  end

  describe '#get_chat_message' do
    it 'retrieves a specific message' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm1' })
      allow(graph_conn).to receive(:get).with('chats/c1/messages/m1').and_return(response)

      result = runner.get_chat_message(chat_id: 'c1', message_id: 'm1')
      expect(result[:result]['id']).to eq('m1')
    end
  end

  describe '#send_chat_message' do
    it 'sends a text message to a chat' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm2' })
      allow(graph_conn).to receive(:post).with('chats/c1/messages', hash_including(
                                                                      body: { contentType: 'text', content: 'Hi there' }
                                                                    )).and_return(response)

      result = runner.send_chat_message(chat_id: 'c1', content: 'Hi there')
      expect(result[:result]['id']).to eq('m2')
    end
  end

  describe '#reply_to_chat_message' do
    it 'replies to a specific message' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm3' })
      allow(graph_conn).to receive(:post).with('chats/c1/messages/m1/replies', anything).and_return(response)

      result = runner.reply_to_chat_message(chat_id: 'c1', message_id: 'm1', content: 'Reply text')
      expect(result[:result]['id']).to eq('m3')
    end
  end
end
