# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Ownership do
  let(:runner) { Object.new.extend(described_class) }
  let(:conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(conn)
  end

  let(:teams_body) do
    {
      'value' => [
        { 'id' => 'team-1', 'displayName' => 'Platform Team', 'mail' => 'platform@example.com' },
        { 'id' => 'team-2', 'displayName' => 'Dev Team', 'mail' => 'dev@example.com' }
      ]
    }
  end

  let(:owners_body_with_owner) do
    {
      'value' => [
        { 'id' => 'user-1', 'displayName' => 'Jane Doe', 'mail' => 'jane.doe@example.com' }
      ]
    }
  end

  let(:owners_body_empty) { { 'value' => [] } }

  let(:teams_params) do
    {
      '$filter' => "resourceProvisioningOptions/Any(x:x eq 'Team')",
      '$select' => 'id,displayName,mail'
    }
  end

  let(:owners_params) { { '$select' => 'id,displayName,mail' } }

  describe '#sync_owners' do
    context 'when team_id is given' do
      it 'returns owners for the specific team' do
        allow(conn).to receive(:get)
          .with('groups/team-1/owners', owners_params)
          .and_return(instance_double(Faraday::Response, body: owners_body_with_owner))

        result = runner.sync_owners(team_id: 'team-1')
        expect(result[:owners].length).to eq(1)
        expect(result[:owners].first['displayName']).to eq('Jane Doe')
        expect(result[:team_count]).to eq(1)
        expect(result[:synced_at]).not_to be_nil
      end

      it 'returns empty owners array when team has no owners' do
        allow(conn).to receive(:get)
          .with('groups/team-1/owners', owners_params)
          .and_return(instance_double(Faraday::Response, body: owners_body_empty))

        result = runner.sync_owners(team_id: 'team-1')
        expect(result[:owners]).to be_empty
        expect(result[:team_count]).to eq(1)
      end

      it 'includes synced_at timestamp' do
        allow(conn).to receive(:get)
          .with('groups/team-1/owners', owners_params)
          .and_return(instance_double(Faraday::Response, body: owners_body_with_owner))

        result = runner.sync_owners(team_id: 'team-1')
        expect(result[:synced_at]).to match(/\d{4}-\d{2}-\d{2}T/)
      end
    end

    context 'when team_id is nil (all teams)' do
      before do
        allow(conn).to receive(:get)
          .with('groups', teams_params)
          .and_return(instance_double(Faraday::Response, body: teams_body))
        allow(conn).to receive(:get)
          .with('groups/team-1/owners', owners_params)
          .and_return(instance_double(Faraday::Response, body: owners_body_with_owner))
        allow(conn).to receive(:get)
          .with('groups/team-2/owners', owners_params)
          .and_return(instance_double(Faraday::Response, body: owners_body_empty))
      end

      it 'returns owners across all teams' do
        result = runner.sync_owners
        expect(result[:team_count]).to eq(2)
        expect(result[:owners].length).to eq(1)
      end

      it 'merges team_id into each owner entry' do
        result = runner.sync_owners
        expect(result[:owners].first['team_id']).to eq('team-1')
      end

      it 'includes synced_at' do
        result = runner.sync_owners
        expect(result[:synced_at]).not_to be_nil
      end
    end

    context 'when a Graph API error occurs' do
      it 'returns an error hash' do
        allow(conn).to receive(:get).and_raise(StandardError, 'network failure')
        result = runner.sync_owners(team_id: 'team-1')
        expect(result[:error]).to eq('network failure')
      end
    end
  end

  describe '#detect_orphans' do
    before do
      allow(conn).to receive(:get)
        .with('groups', teams_params)
        .and_return(instance_double(Faraday::Response, body: teams_body))
    end

    context 'when one team has no owners' do
      before do
        allow(conn).to receive(:get)
          .with('groups/team-1/owners', owners_params)
          .and_return(instance_double(Faraday::Response, body: owners_body_with_owner))
        allow(conn).to receive(:get)
          .with('groups/team-2/owners', owners_params)
          .and_return(instance_double(Faraday::Response, body: owners_body_empty))
      end

      it 'identifies the orphaned team' do
        result = runner.detect_orphans
        expect(result[:orphan_count]).to eq(1)
        expect(result[:orphaned_teams].first[:id]).to eq('team-2')
        expect(result[:orphaned_teams].first[:display_name]).to eq('Dev Team')
      end

      it 'reports the correct total_scanned count' do
        result = runner.detect_orphans
        expect(result[:total_scanned]).to eq(2)
      end
    end

    context 'when all teams have owners' do
      before do
        allow(conn).to receive(:get)
          .with('groups/team-1/owners', owners_params)
          .and_return(instance_double(Faraday::Response, body: owners_body_with_owner))
        allow(conn).to receive(:get)
          .with('groups/team-2/owners', owners_params)
          .and_return(instance_double(Faraday::Response, body: owners_body_with_owner))
      end

      it 'returns zero orphans' do
        result = runner.detect_orphans
        expect(result[:orphan_count]).to eq(0)
        expect(result[:orphaned_teams]).to be_empty
      end
    end

    context 'when all teams are orphaned' do
      before do
        allow(conn).to receive(:get)
          .with('groups/team-1/owners', owners_params)
          .and_return(instance_double(Faraday::Response, body: owners_body_empty))
        allow(conn).to receive(:get)
          .with('groups/team-2/owners', owners_params)
          .and_return(instance_double(Faraday::Response, body: owners_body_empty))
      end

      it 'returns all teams as orphaned' do
        result = runner.detect_orphans
        expect(result[:orphan_count]).to eq(2)
        expect(result[:total_scanned]).to eq(2)
      end
    end

    context 'when a Graph API error occurs' do
      it 'returns an error hash' do
        allow(conn).to receive(:get).and_raise(StandardError, 'timeout')
        result = runner.detect_orphans
        expect(result[:error]).to eq('timeout')
      end
    end
  end

  describe '#get_team_owners' do
    it 'returns owner list for the given team_id' do
      allow(conn).to receive(:get)
        .with('groups/team-1/owners', owners_params)
        .and_return(instance_double(Faraday::Response, body: owners_body_with_owner))

      result = runner.get_team_owners(team_id: 'team-1')
      expect(result[:team_id]).to eq('team-1')
      expect(result[:owners].length).to eq(1)
      expect(result[:owners].first['mail']).to eq('jane.doe@example.com')
    end

    it 'returns empty owners array when team has no owners' do
      allow(conn).to receive(:get)
        .with('groups/team-1/owners', owners_params)
        .and_return(instance_double(Faraday::Response, body: owners_body_empty))

      result = runner.get_team_owners(team_id: 'team-1')
      expect(result[:team_id]).to eq('team-1')
      expect(result[:owners]).to be_empty
    end

    it 'returns correct structure with team_id and owners keys' do
      allow(conn).to receive(:get)
        .with('groups/team-1/owners', owners_params)
        .and_return(instance_double(Faraday::Response, body: owners_body_with_owner))

      result = runner.get_team_owners(team_id: 'team-1')
      expect(result.keys).to contain_exactly(:team_id, :owners)
    end

    it 'returns an error hash on failure' do
      allow(conn).to receive(:get).and_raise(StandardError, 'unauthorized')
      result = runner.get_team_owners(team_id: 'team-1')
      expect(result[:error]).to eq('unauthorized')
    end
  end
end
