# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Transcripts do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_transcripts' do
    it 'lists transcripts for a meeting' do
      response = instance_double(Faraday::Response,
                                 body: { 'value' => [{ 'id' => 't1', 'createdDateTime' => '2026-03-15T12:00:00Z' }] })
      allow(graph_conn).to receive(:get)
        .with('users/u1/onlineMeetings/m1/transcripts')
        .and_return(response)

      result = runner.list_transcripts(user_id: 'u1', meeting_id: 'm1')
      expect(result[:result]['value'].first['id']).to eq('t1')
    end
  end

  describe '#get_transcript' do
    it 'retrieves transcript metadata' do
      response = instance_double(Faraday::Response, body: { 'id' => 't1', 'createdDateTime' => '2026-03-15T12:00:00Z' })
      allow(graph_conn).to receive(:get)
        .with('users/u1/onlineMeetings/m1/transcripts/t1')
        .and_return(response)

      result = runner.get_transcript(user_id: 'u1', meeting_id: 'm1', transcript_id: 't1')
      expect(result[:result]['id']).to eq('t1')
    end
  end

  describe '#get_transcript_content' do
    it 'retrieves transcript content as VTT by default' do
      vtt_body = "WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nHello everyone"
      response = instance_double(Faraday::Response, body: vtt_body)
      allow(graph_conn).to receive(:get) do |_path, _params, &block|
        req = double('request', headers: {})
        block&.call(req)
        response
      end

      result = runner.get_transcript_content(user_id: 'u1', meeting_id: 'm1', transcript_id: 't1')
      expect(result[:result]).to include('WEBVTT')
    end

    it 'sets Accept header to text/vtt for default format' do
      response = instance_double(Faraday::Response, body: 'vtt content')
      headers = {}
      allow(graph_conn).to receive(:get) do |_path, _params, &block|
        req = double('request', headers: headers)
        block&.call(req)
        response
      end

      runner.get_transcript_content(user_id: 'u1', meeting_id: 'm1', transcript_id: 't1')
      expect(headers['Accept']).to eq('text/vtt')
    end

    it 'sets Accept header for docx format' do
      response = instance_double(Faraday::Response, body: 'binary-docx-content')
      headers = {}
      allow(graph_conn).to receive(:get) do |_path, _params, &block|
        req = double('request', headers: headers)
        block&.call(req)
        response
      end

      runner.get_transcript_content(user_id: 'u1', meeting_id: 'm1', transcript_id: 't1', format: :docx)
      expect(headers['Accept']).to eq('application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    end

    it 'raises KeyError for unknown format' do
      expect do
        runner.get_transcript_content(user_id: 'u1', meeting_id: 'm1', transcript_id: 't1', format: :pdf)
      end.to raise_error(KeyError)
    end
  end
end
