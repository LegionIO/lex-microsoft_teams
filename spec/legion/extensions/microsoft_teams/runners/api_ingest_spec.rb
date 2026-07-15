# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::ApiIngest do
  let(:runner) { Object.new.extend(described_class) }
  let(:memory_runner) { double('memory_runner') }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:memory_runner).and_return(memory_runner)
    allow(memory_runner).to receive(:store_trace).and_return({ success: true, trace_id: 'trace-1' })
    allow(memory_runner).to receive(:retrieve_by_domain).and_return([])
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
    allow(runner).to receive(:permission_denied?).and_return(false)
    allow(runner).to receive(:record_denial)
    allow(runner).to receive(:cache_available?).and_return(false)
  end

  describe 'throttle propagation (A1)' do
    let(:throttled_error) do
      Legion::Extensions::MicrosoftTeams::Errors::Throttled.new(
        status: 429, retry_after: 30.0, request: '/me/people'
      )
    end

    context 'when fetch_top_people encounters Throttled' do
      it 'raises Errors::Throttled instead of swallowing it' do
        allow(graph_conn).to receive(:get).and_raise(throttled_error)

        expect do
          runner.send(:fetch_top_people, token: 'tok', top: 10)
        end.to raise_error(Legion::Extensions::MicrosoftTeams::Errors::Throttled)
      end
    end

    context 'when fetch_one_on_one_chats encounters Throttled' do
      it 'raises Errors::Throttled instead of swallowing it' do
        allow(graph_conn).to receive(:get).and_raise(throttled_error)

        expect do
          runner.send(:fetch_one_on_one_chats, token: 'tok')
        end.to raise_error(Legion::Extensions::MicrosoftTeams::Errors::Throttled)
      end
    end

    context 'when build_chat_member_index encounters Throttled' do
      it 'raises Errors::Throttled instead of swallowing it' do
        allow(runner).to receive(:cached_graph_get).and_raise(throttled_error)
        chats = [{ 'id' => 'chat-1', 'chatType' => 'oneOnOne' }]

        expect do
          runner.send(:build_chat_member_index, conn: graph_conn, chats: chats)
        end.to raise_error(Legion::Extensions::MicrosoftTeams::Errors::Throttled)
      end
    end

    context 'when fetch_chat_messages encounters Throttled' do
      it 'raises Errors::Throttled instead of swallowing it' do
        allow(runner).to receive(:get_extended_hwm).and_return(nil)
        allow(graph_conn).to receive(:get).and_raise(throttled_error)

        expect do
          runner.send(:fetch_chat_messages, conn: graph_conn, chat_id: 'chat-1')
        end.to raise_error(Legion::Extensions::MicrosoftTeams::Errors::Throttled)
      end
    end
  end

  describe 'non-2xx status handling (A1)' do
    context 'when fetch_top_people receives a 403' do
      let(:forbidden_resp) do
        instance_double(Faraday::Response,
                        status: 403,
                        body:   { 'error' => { 'code'    => 'Authorization_RequestDenied',
                                               'message' => 'Insufficient privileges' } })
      end

      before do
        allow(graph_conn).to receive(:get).and_return(forbidden_resp)
      end

      it 'returns an empty array' do
        result = runner.send(:fetch_top_people, token: 'tok', top: 10)
        expect(result).to eq([])
      end

      it 'increments fetch_failures' do
        runner.instance_variable_set(:@fetch_failures, 0)
        runner.send(:fetch_top_people, token: 'tok', top: 10)
        expect(runner.instance_variable_get(:@fetch_failures)).to eq(1)
      end
    end

    context 'when fetch_chat_messages receives a 404' do
      let(:not_found_resp) do
        instance_double(Faraday::Response,
                        status: 404,
                        body:   { 'error' => { 'code'    => 'ResourceNotFound',
                                               'message' => 'Chat not found' } })
      end

      before do
        allow(runner).to receive(:get_extended_hwm).and_return(nil)
        allow(graph_conn).to receive(:get).and_return(not_found_resp)
      end

      it 'returns an empty array' do
        result = runner.send(:fetch_chat_messages, conn: graph_conn, chat_id: 'chat-1')
        expect(result).to eq([])
      end

      it 'increments fetch_failures' do
        runner.instance_variable_set(:@fetch_failures, 0)
        runner.send(:fetch_chat_messages, conn: graph_conn, chat_id: 'chat-1')
        expect(runner.instance_variable_get(:@fetch_failures)).to eq(1)
      end
    end

    context 'when ingest_api runs with fetch failures' do
      let(:people_resp) do
        instance_double(Faraday::Response,
                        status: 200,
                        body:   { 'value' => [{ 'displayName'          => 'Bob',
                                                'scoredEmailAddresses' => [{ 'address' => 'bob@test.com', 'relevanceScore' => 8 }],
                                                'id'                   => 'user-1' }] })
      end
      let(:chats_resp) do
        instance_double(Faraday::Response,
                        status: 200,
                        body:   { 'value' => [{ 'id' => 'chat-1', 'chatType' => 'oneOnOne' }] })
      end
      let(:messages_403_resp) do
        instance_double(Faraday::Response,
                        status: 403,
                        body:   { 'error' => { 'code' => 'Forbidden', 'message' => 'Access denied' } })
      end

      before do
        allow(runner).to receive(:memory_available?).and_return(true)
        allow(runner).to receive(:restore_hwm_from_traces)
        allow(runner).to receive(:get_extended_hwm).and_return(nil)
        allow(runner).to receive(:load_existing_hashes).and_return(Set.new)
        allow(runner).to receive(:cached_graph_get).and_return(
          { 'value' => [{ 'email' => 'bob@test.com', 'userId' => 'user-1', 'displayName' => 'Bob' }] }
        )
        allow(graph_conn).to receive(:get).with('me/people', anything).and_return(people_resp)
        allow(graph_conn).to receive(:get).with('me/chats', anything).and_return(chats_resp)
        allow(graph_conn).to receive(:get).with('chats/chat-1/messages', anything).and_return(messages_403_resp)
      end

      it 'includes fetch_failures in the result hash' do
        result = runner.ingest_api(token: 'tok')
        expect(result[:result][:fetch_failures]).to be >= 1
      end
    end
  end
end
