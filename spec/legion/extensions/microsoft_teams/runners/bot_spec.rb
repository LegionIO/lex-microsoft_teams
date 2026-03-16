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
        service_url:     'https://smba.trafficmanager.net/teams/',
        conversation_id: 'conv1',
        activity_id:     'a1',
        text:            'Reply text'
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
        bot_id:      'bot-id',
        user_id:     'user-id'
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

  describe '#handle_message' do
    let(:bot) { Object.new.extend(described_class) }
    let(:session_manager) do
      Legion::Extensions::MicrosoftTeams::Helpers::SessionManager.new
    end
    let(:faraday_response) { instance_double(Faraday::Response, body: { 'id' => 'msg-1' }) }
    let(:conn) { instance_double(Faraday::Connection, post: faraday_response) }

    before do
      allow(bot).to receive(:session_manager).and_return(session_manager)
      allow(bot).to receive(:llm_available?).and_return(false)
      allow(bot).to receive(:graph_connection).and_return(conn)
    end

    it 'returns a result hash' do
      result = bot.handle_message(
        chat_id: '19:abc', conversation_id: '19:abc', text: 'hello',
        from: { id: 'user1', name: 'Jane' }, owner_id: 'user1'
      )
      expect(result).to have_key(:result)
    end

    it 'echoes when LLM is unavailable' do
      bot.handle_message(
        chat_id: '19:abc', conversation_id: '19:abc', text: 'hello',
        from: { id: 'user1', name: 'Jane' }, owner_id: 'user1'
      )
      expect(conn).to have_received(:post).with(
        '/chats/19:abc/messages',
        hash_including(:body)
      )
    end

    it 'tracks messages in session' do
      bot.handle_message(
        chat_id: '19:abc', conversation_id: '19:abc', text: 'hello',
        from: { id: 'user1', name: 'Jane' }, owner_id: 'user1'
      )
      msgs = session_manager.recent_messages(conversation_id: '19:abc')
      expect(msgs.length).to eq(2) # user + assistant
      expect(msgs.first[:role]).to eq(:user)
      expect(msgs.last[:role]).to eq(:assistant)
    end

    it 'uses Bot Framework reply when service_url is present' do
      allow(bot).to receive(:reply_to_activity).and_return({ result: { id: 'act-1' } })
      bot.handle_message(
        chat_id: '19:abc', conversation_id: '19:abc', text: 'hello',
        from: { id: 'user1', name: 'Jane' }, owner_id: 'user1',
        service_url: 'https://smba.trafficmanager.net/teams/', activity_id: 'act-123'
      )
      expect(bot).to have_received(:reply_to_activity)
    end
  end

  describe '#observe_message' do
    let(:bot) { Object.new.extend(described_class) }

    before do
      allow(bot).to receive(:observe_enabled?).and_return(false)
    end

    it 'returns skipped when observe is disabled' do
      result = bot.observe_message(
        chat_id: '19:xyz', owner_id: 'user1', text: 'send the report',
        from: { id: 'sarah', name: 'Sarah' }, peer_name: 'Sarah'
      )
      expect(result).to eq({ result: :skipped, reason: :observe_disabled })
    end

    context 'when observe is enabled' do
      before do
        allow(bot).to receive(:observe_enabled?).and_return(true)
        allow(bot).to receive(:llm_available?).and_return(false)
        allow(bot).to receive(:memory_available?).and_return(false)
      end

      it 'returns result with raw text when LLM unavailable' do
        result = bot.observe_message(
          chat_id: '19:xyz', owner_id: 'user1', text: 'send the report',
          from: { id: 'sarah', name: 'Sarah' }, peer_name: 'Sarah'
        )
        expect(result[:result]).to eq({ raw_text: 'send the report' })
      end
    end
  end

  describe '#handle_command' do
    let(:bot) { Object.new.extend(described_class) }
    let(:registry) { Legion::Extensions::MicrosoftTeams::Helpers::SubscriptionRegistry.new }
    let(:graph_conn) { instance_double(Faraday::Connection) }

    before do
      allow(bot).to receive(:subscription_registry).and_return(registry)
      allow(bot).to receive(:graph_connection).and_return(graph_conn)
    end

    describe 'watch command' do
      it 'recognizes "watch Sarah"' do
        allow(bot).to receive(:find_chat_with_person).and_return({ id: 'chat-99' })
        result = bot.handle_command(text: 'watch Sarah', owner_id: 'user1', chat_id: '19:bot')
        expect(result).not_to be_nil
        expect(result[:command]).to eq(:watch)
      end

      it 'returns nil for non-command text' do
        result = bot.handle_command(text: 'hello there', owner_id: 'user1', chat_id: '19:bot')
        expect(result).to be_nil
      end
    end

    describe 'unwatch command' do
      before do
        registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
      end

      it 'recognizes "unwatch Sarah"' do
        result = bot.handle_command(text: 'unwatch Sarah', owner_id: 'user1', chat_id: '19:bot')
        expect(result).not_to be_nil
        expect(result[:command]).to eq(:unwatch)
      end

      it 'recognizes "stop watching Sarah"' do
        result = bot.handle_command(text: 'stop watching Sarah', owner_id: 'user1', chat_id: '19:bot')
        expect(result[:command]).to eq(:unwatch)
      end
    end

    describe 'list command' do
      it 'recognizes "watching"' do
        result = bot.handle_command(text: 'watching', owner_id: 'user1', chat_id: '19:bot')
        expect(result[:command]).to eq(:list)
      end

      it 'recognizes "list"' do
        result = bot.handle_command(text: 'list', owner_id: 'user1', chat_id: '19:bot')
        expect(result[:command]).to eq(:list)
      end

      it 'recognizes "subscriptions"' do
        result = bot.handle_command(text: 'subscriptions', owner_id: 'user1', chat_id: '19:bot')
        expect(result[:command]).to eq(:list)
      end
    end

    describe 'pause command' do
      before do
        registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
      end

      it 'recognizes "pause Sarah"' do
        result = bot.handle_command(text: 'pause Sarah', owner_id: 'user1', chat_id: '19:bot')
        expect(result[:command]).to eq(:pause)
      end
    end

    describe 'resume command' do
      before do
        registry.subscribe(owner_id: 'user1', chat_id: 'chat-1', peer_name: 'Sarah')
        registry.pause(owner_id: 'user1', chat_id: 'chat-1')
      end

      it 'recognizes "resume Sarah"' do
        result = bot.handle_command(text: 'resume Sarah', owner_id: 'user1', chat_id: '19:bot')
        expect(result[:command]).to eq(:resume)
      end
    end
  end

  describe '#handle_message with commands' do
    let(:bot) { Object.new.extend(described_class) }
    let(:session_manager) { Legion::Extensions::MicrosoftTeams::Helpers::SessionManager.new }
    let(:registry) { Legion::Extensions::MicrosoftTeams::Helpers::SubscriptionRegistry.new }
    let(:faraday_response) { instance_double(Faraday::Response, body: { 'id' => 'msg-1' }) }
    let(:conn) { instance_double(Faraday::Connection, post: faraday_response) }

    before do
      allow(bot).to receive(:session_manager).and_return(session_manager)
      allow(bot).to receive(:subscription_registry).and_return(registry)
      allow(bot).to receive(:llm_available?).and_return(false)
      allow(bot).to receive(:graph_connection).and_return(conn)
    end

    it 'handles list command and sends reply' do
      result = bot.handle_message(
        chat_id: '19:abc', conversation_id: '19:abc', text: 'watching',
        from: { id: 'user1', name: 'Jane' }, owner_id: 'user1'
      )
      expect(result).to have_key(:result)
      expect(result[:result][:command]).to eq(:list)
    end

    it 'falls through to LLM for non-commands' do
      result = bot.handle_message(
        chat_id: '19:abc', conversation_id: '19:abc', text: 'hello friend',
        from: { id: 'user1', name: 'Jane' }, owner_id: 'user1'
      )
      expect(result).to have_key(:result)
      expect(result[:result]).not_to have_key(:command)
    end
  end
end
