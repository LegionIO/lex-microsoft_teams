# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Channels do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_channels' do
    it 'lists channels for a team' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'ch1', 'displayName' => 'General' }] })
      allow(graph_conn).to receive(:get).with('/teams/t1/channels').and_return(response)

      result = runner.list_channels(team_id: 't1')
      expect(result[:result]['value'].first['displayName']).to eq('General')
    end
  end

  describe '#get_channel' do
    it 'retrieves a channel by id' do
      response = instance_double(Faraday::Response, body: { 'id' => 'ch1' })
      allow(graph_conn).to receive(:get).with('/teams/t1/channels/ch1').and_return(response)

      result = runner.get_channel(team_id: 't1', channel_id: 'ch1')
      expect(result[:result]['id']).to eq('ch1')
    end
  end

  describe '#create_channel' do
    it 'creates a new channel' do
      response = instance_double(Faraday::Response, body: { 'id' => 'ch2', 'displayName' => 'Dev' })
      allow(graph_conn).to receive(:post).with('/teams/t1/channels', hash_including(displayName: 'Dev')).and_return(response)

      result = runner.create_channel(team_id: 't1', display_name: 'Dev')
      expect(result[:result]['displayName']).to eq('Dev')
    end
  end

  describe '#delete_channel' do
    it 'deletes a channel' do
      response = instance_double(Faraday::Response, body: '')
      allow(graph_conn).to receive(:delete).with('/teams/t1/channels/ch2').and_return(response)

      result = runner.delete_channel(team_id: 't1', channel_id: 'ch2')
      expect(result[:result]).to eq('')
    end
  end

  describe '#list_channel_members' do
    it 'lists members of a channel' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'displayName' => 'User B' }] })
      allow(graph_conn).to receive(:get).with('/teams/t1/channels/ch1/members').and_return(response)

      result = runner.list_channel_members(team_id: 't1', channel_id: 'ch1')
      expect(result[:result]['value']).not_to be_empty
    end
  end
end
