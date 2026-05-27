# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::MeetingArtifacts do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_meeting_artifacts' do
    it 'lists artifacts for a meeting using the default user' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'a1', 'artifactType' => 'recording' }] })
      allow(graph_conn).to receive(:get)
        .with('me/onlineMeetings/m1/artifacts', { '$top' => 50 })
        .and_return(response)

      result = runner.list_meeting_artifacts(meeting_id: 'm1')
      expect(result[:result]['value'].first['id']).to eq('a1')
    end

    it 'uses a specified user_id in the path' do
      response = instance_double(Faraday::Response, body: { 'value' => [] })
      allow(graph_conn).to receive(:get)
        .with('users/u1/onlineMeetings/m1/artifacts', { '$top' => 50 })
        .and_return(response)

      result = runner.list_meeting_artifacts(meeting_id: 'm1', user_id: 'u1')
      expect(result[:result]['value']).to eq([])
    end
  end

  describe '#get_meeting_artifact' do
    it 'retrieves a single artifact by id' do
      response = instance_double(Faraday::Response, body: { 'id' => 'a1', 'artifactType' => 'recording' })
      allow(graph_conn).to receive(:get)
        .with('users/u1/onlineMeetings/m1/artifacts/a1')
        .and_return(response)

      result = runner.get_meeting_artifact(meeting_id: 'm1', artifact_id: 'a1', user_id: 'u1')
      expect(result[:result]['artifactType']).to eq('recording')
    end

    it 'uses me as default user_id' do
      response = instance_double(Faraday::Response, body: { 'id' => 'a2' })
      allow(graph_conn).to receive(:get)
        .with('me/onlineMeetings/m2/artifacts/a2')
        .and_return(response)

      result = runner.get_meeting_artifact(meeting_id: 'm2', artifact_id: 'a2')
      expect(result[:result]['id']).to eq('a2')
    end
  end
end
