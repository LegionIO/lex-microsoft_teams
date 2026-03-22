# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::ProfileIngest do
  it 'responds to full_ingest as a module method' do
    expect(described_class).to respond_to(:full_ingest)
  end

  it 'responds to incremental_sync as a module method' do
    expect(described_class).to respond_to(:incremental_sync)
  end

  let(:runner) { Object.new.extend(described_class) }
  let(:memory_runner) { double('memory_runner') }
  let(:graph_conn) { instance_double(Faraday::Connection) }
  let(:response) { instance_double(Faraday::Response) }

  before do
    allow(runner).to receive(:memory_runner).and_return(memory_runner)
    allow(memory_runner).to receive(:store_trace).and_return({ success: true })
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
    allow(runner).to receive(:permission_denied?).and_return(false)
    allow(runner).to receive(:record_denial)
  end

  describe '#ingest_self' do
    let(:profile_body) do
      { 'displayName' => 'Jane Doe', 'mail' => 'jane@example.com',
        'jobTitle' => 'Engineer', 'department' => 'Platform', 'officeLocation' => 'Minneapolis' }
    end

    let(:presence_response) { instance_double(Faraday::Response) }

    before do
      allow(graph_conn).to receive(:get).with('me').and_return(response)
      allow(response).to receive(:body).and_return(profile_body)
      allow(graph_conn).to receive(:get).with('me/presence').and_return(presence_response)
      allow(presence_response).to receive(:body).and_return({})
    end

    it 'stores an identity trace with self tags' do
      expect(memory_runner).to receive(:store_trace).with(hash_including(
                                                            type:        :identity,
                                                            domain_tags: %w[teams self owner]
                                                          ))
      runner.ingest_self(token: 'tok')
    end

    it 'returns the profile data' do
      result = runner.ingest_self(token: 'tok')
      expect(result[:profile]['displayName']).to eq('Jane Doe')
    end
  end

  describe '#ingest_people' do
    let(:people_body) do
      { 'value' => [
        { 'displayName' => 'Bob', 'scoredEmailAddresses' => [{ 'address' => 'bob@example.com', 'relevanceScore' => 8.0 }],
          'jobTitle' => 'Manager', 'department' => 'Eng' },
        { 'displayName' => 'Alice', 'scoredEmailAddresses' => [{ 'address' => 'alice@example.com', 'relevanceScore' => 5.0 }],
          'jobTitle' => 'Designer', 'department' => 'UX' }
      ] }
    end

    before do
      allow(graph_conn).to receive(:get).with('me/people', anything).and_return(response)
      allow(response).to receive(:body).and_return(people_body)
    end

    it 'stores a semantic trace per person' do
      expect(memory_runner).to receive(:store_trace).twice
      runner.ingest_people(token: 'tok', top: 25)
    end

    it 'returns people sorted by relevance score' do
      result = runner.ingest_people(token: 'tok', top: 25)
      expect(result[:people].first['displayName']).to eq('Bob')
    end

    it 'skips when permission is denied' do
      allow(runner).to receive(:permission_denied?).with('/me/people').and_return(true)
      result = runner.ingest_people(token: 'tok', top: 25)
      expect(result[:skipped]).to be true
    end
  end

  describe '#ingest_conversations' do
    let(:chats_body) { { 'value' => [{ 'id' => 'chat-1', 'chatType' => 'oneOnOne', 'members' => [] }] } }

    before do
      allow(graph_conn).to receive(:get).with('me/chats', anything).and_return(response)
      allow(response).to receive(:body).and_return(chats_body)
    end

    it 'skips when no people are provided' do
      result = runner.ingest_conversations(token: 'tok', people: [], top_people: 10)
      expect(result[:ingested]).to eq(0)
    end
  end

  describe '#ingest_teams_and_meetings' do
    let(:teams_body) { { 'value' => [{ 'id' => 'team-1', 'displayName' => 'Platform' }] } }
    let(:members_body) { { 'value' => [{ 'displayName' => 'Jane' }] } }
    let(:meetings_body) { { 'value' => [] } }

    before do
      allow(graph_conn).to receive(:get).with('me/joinedTeams').and_return(response)
      allow(response).to receive(:body).and_return(teams_body)
      meeting_resp = instance_double(Faraday::Response, body: meetings_body)
      members_resp = instance_double(Faraday::Response, body: members_body)
      allow(graph_conn).to receive(:get).with('teams/team-1/members').and_return(members_resp)
      allow(graph_conn).to receive(:get).with('me/onlineMeetings').and_return(meeting_resp)
    end

    it 'stores semantic traces for teams' do
      expect(memory_runner).to receive(:store_trace).at_least(:once)
      runner.ingest_teams_and_meetings(token: 'tok')
    end
  end

  describe '#full_ingest' do
    it 'runs all four phases in order' do
      expect(runner).to receive(:ingest_self).ordered.and_return({ profile: {} })
      expect(runner).to receive(:ingest_people).ordered.and_return({ people: [], skipped: false })
      expect(runner).to receive(:ingest_conversations).ordered.and_return({ ingested: 0 })
      expect(runner).to receive(:ingest_teams_and_meetings).ordered.and_return({ teams: 0 })
      runner.full_ingest(token: 'tok')
    end
  end
end
