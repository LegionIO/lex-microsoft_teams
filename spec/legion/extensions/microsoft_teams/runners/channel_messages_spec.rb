# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::ChannelMessages do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_channel_messages' do
    it 'lists messages in a channel' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'cm1' }] })
      allow(graph_conn).to receive(:get).with('teams/t1/channels/ch1/messages', { '$top' => 50 }).and_return(response)

      result = runner.list_channel_messages(team_id: 't1', channel_id: 'ch1')
      expect(result[:result]['value'].first['id']).to eq('cm1')
    end
  end

  describe '#send_channel_message' do
    it 'sends a message to a channel' do
      response = instance_double(Faraday::Response, body: { 'id' => 'cm2' })
      allow(graph_conn).to receive(:post).with(
        'teams/t1/channels/ch1/messages',
        hash_including(body: { contentType: 'text', content: 'Channel msg' })
      ).and_return(response)

      result = runner.send_channel_message(team_id: 't1', channel_id: 'ch1', content: 'Channel msg')
      expect(result[:result]['id']).to eq('cm2')
    end
  end

  describe '#reply_to_channel_message' do
    it 'replies to a channel message' do
      response = instance_double(Faraday::Response, body: { 'id' => 'cm3' })
      allow(graph_conn).to receive(:post).with(
        'teams/t1/channels/ch1/messages/cm1/replies', anything
      ).and_return(response)

      result = runner.reply_to_channel_message(team_id: 't1', channel_id: 'ch1', message_id: 'cm1', content: 'Reply')
      expect(result[:result]['id']).to eq('cm3')
    end
  end
end
