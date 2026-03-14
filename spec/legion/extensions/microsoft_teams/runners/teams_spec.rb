# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Teams do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_joined_teams' do
    it 'lists teams for the current user' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 't1', 'displayName' => 'Team A' }] })
      allow(graph_conn).to receive(:get).with('/me/joinedTeams').and_return(response)

      result = runner.list_joined_teams
      expect(result[:result]['value'].first['displayName']).to eq('Team A')
    end
  end

  describe '#get_team' do
    it 'retrieves a team by id' do
      response = instance_double(Faraday::Response, body: { 'id' => 't1', 'displayName' => 'Team A' })
      allow(graph_conn).to receive(:get).with('/teams/t1').and_return(response)

      result = runner.get_team(team_id: 't1')
      expect(result[:result]['id']).to eq('t1')
    end
  end

  describe '#list_team_members' do
    it 'lists members of a team' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'displayName' => 'User A' }] })
      allow(graph_conn).to receive(:get).with('/teams/t1/members').and_return(response)

      result = runner.list_team_members(team_id: 't1')
      expect(result[:result]['value']).not_to be_empty
    end
  end
end
