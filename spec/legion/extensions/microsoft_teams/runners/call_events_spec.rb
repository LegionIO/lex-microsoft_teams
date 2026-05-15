# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::CallEvents do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_call_sessions' do
    it 'lists all sessions for a call record' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 's1' }] })
      allow(graph_conn).to receive(:get)
        .with('communications/callRecords/cr1/sessions')
        .and_return(response)

      result = runner.list_call_sessions(call_id: 'cr1')
      expect(result[:result]['value'].first['id']).to eq('s1')
    end
  end

  describe '#get_call_session' do
    it 'retrieves a single call session' do
      response = instance_double(Faraday::Response, body: { 'id' => 's1', 'modalities' => ['audio'] })
      allow(graph_conn).to receive(:get)
        .with('communications/callRecords/cr1/sessions/s1')
        .and_return(response)

      result = runner.get_call_session(call_id: 'cr1', session_id: 's1')
      expect(result[:result]['modalities']).to include('audio')
    end
  end

  describe '#list_session_segments' do
    it 'lists segments for a session' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'seg1' }, { 'id' => 'seg2' }] })
      allow(graph_conn).to receive(:get)
        .with('communications/callRecords/cr1/sessions/s1/segments')
        .and_return(response)

      result = runner.list_session_segments(call_id: 'cr1', session_id: 's1')
      expect(result[:result]['value'].length).to eq(2)
    end
  end
end
