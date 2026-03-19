# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Chats do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_chats' do
    it 'lists chats for the current user' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'c1' }] })
      allow(graph_conn).to receive(:get).with('me/chats', { '$top' => 50 }).and_return(response)

      result = runner.list_chats
      expect(result[:result]['value'].first['id']).to eq('c1')
    end
  end

  describe '#get_chat' do
    it 'retrieves a chat by id' do
      response = instance_double(Faraday::Response, body: { 'id' => 'c1', 'chatType' => 'oneOnOne' })
      allow(graph_conn).to receive(:get).with('chats/c1').and_return(response)

      result = runner.get_chat(chat_id: 'c1')
      expect(result[:result]['chatType']).to eq('oneOnOne')
    end
  end

  describe '#create_chat' do
    it 'creates a new 1:1 chat' do
      members = [{ '@odata.type' => '#microsoft.graph.aadUserConversationMember', 'roles' => ['owner'] }]
      response = instance_double(Faraday::Response, body: { 'id' => 'c2', 'chatType' => 'oneOnOne' })
      allow(graph_conn).to receive(:post).with('chats', hash_including(chatType: 'oneOnOne')).and_return(response)

      result = runner.create_chat(members: members)
      expect(result[:result]['id']).to eq('c2')
    end
  end

  describe '#list_chat_members' do
    it 'lists members of a chat' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'displayName' => 'User A' }] })
      allow(graph_conn).to receive(:get).with('chats/c1/members').and_return(response)

      result = runner.list_chat_members(chat_id: 'c1')
      expect(result[:result]['value']).not_to be_empty
    end
  end
end
