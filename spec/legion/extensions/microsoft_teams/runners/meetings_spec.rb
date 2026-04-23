# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Meetings do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_meetings' do
    it 'lists online meetings for a user' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'm1', 'subject' => 'Standup' }] })
      allow(graph_conn).to receive(:get).with('users/u1/onlineMeetings').and_return(response)

      result = runner.list_meetings(user_id: 'u1')
      expect(result[:result]['value'].first['subject']).to eq('Standup')
    end
  end

  describe '#get_meeting' do
    it 'retrieves a meeting by id' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm1', 'subject' => 'Standup' })
      allow(graph_conn).to receive(:get).with('users/u1/onlineMeetings/m1').and_return(response)

      result = runner.get_meeting(user_id: 'u1', meeting_id: 'm1')
      expect(result[:result]['id']).to eq('m1')
    end
  end

  describe '#create_meeting' do
    it 'creates an online meeting' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm2', 'subject' => 'Review' })
      allow(graph_conn).to receive(:post)
        .with('users/u1/onlineMeetings', hash_including(subject: 'Review'))
        .and_return(response)

      result = runner.create_meeting(user_id: 'u1', subject: 'Review',
                                     start_time: '2026-03-15T10:00:00Z',
                                     end_time: '2026-03-15T11:00:00Z')
      expect(result[:result]['subject']).to eq('Review')
    end
  end

  describe '#update_meeting' do
    it 'updates a meeting' do
      response = instance_double(Faraday::Response, body: { 'id' => 'm1', 'subject' => 'Updated' })
      allow(graph_conn).to receive(:patch)
        .with('users/u1/onlineMeetings/m1', hash_including(subject: 'Updated'))
        .and_return(response)

      result = runner.update_meeting(user_id: 'u1', meeting_id: 'm1', subject: 'Updated')
      expect(result[:result]['subject']).to eq('Updated')
    end
  end

  describe '#delete_meeting' do
    it 'deletes a meeting' do
      response = instance_double(Faraday::Response, body: '')
      allow(graph_conn).to receive(:delete).with('users/u1/onlineMeetings/m1').and_return(response)

      result = runner.delete_meeting(user_id: 'u1', meeting_id: 'm1')
      expect(result[:result]).to eq('')
    end
  end

  describe '#get_meeting_by_join_url' do
    it 'finds a meeting by join URL' do
      response = instance_double(Faraday::Response,
                                 body: { 'value' => [{ 'id' => 'm1', 'joinWebUrl' => 'https://teams.microsoft.com/l/meetup/123' }] })
      allow(graph_conn).to receive(:get)
        .with('users/u1/onlineMeetings',
              { '$filter' => "joinWebUrl eq 'https://teams.microsoft.com/l/meetup/123'" })
        .and_return(response)

      result = runner.get_meeting_by_join_url(user_id: 'u1', join_url: 'https://teams.microsoft.com/l/meetup/123')
      expect(result[:result]['value'].first['id']).to eq('m1')
    end
  end

  describe '#list_attendance_reports' do
    it 'lists attendance reports for a meeting' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'r1' }] })
      allow(graph_conn).to receive(:get).with('users/u1/onlineMeetings/m1/attendanceReports').and_return(response)

      result = runner.list_attendance_reports(user_id: 'u1', meeting_id: 'm1')
      expect(result[:result]['value']).not_to be_empty
    end
  end

  describe '#resolve_meeting' do
    let(:chat_body) do
      { 'id' => '19:meeting_abc@thread.v2',
        'onlineMeetingInfo' => { 'joinWebUrl' => 'https://teams.microsoft.com/l/meetup-join/abc' } }
    end

    it 'resolves a meeting from a chat thread ID' do
      chat_response = instance_double(Faraday::Response, body: chat_body)
      allow(graph_conn).to receive(:get).with('chats/19:meeting_abc@thread.v2').and_return(chat_response)

      meeting_response = instance_double(Faraday::Response,
                                         body: { 'value' => [{ 'id' => 'real-meeting-id', 'subject' => 'Standup' }] })
      allow(graph_conn).to receive(:get)
        .with('me/onlineMeetings', { '$filter' => "joinWebUrl eq 'https://teams.microsoft.com/l/meetup-join/abc'" })
        .and_return(meeting_response)

      result = runner.resolve_meeting(chat_thread_id: '19:meeting_abc@thread.v2')
      expect(result[:result]['id']).to eq('real-meeting-id')
    end

    it 'returns error when chat has no onlineMeetingInfo' do
      chat_response = instance_double(Faraday::Response, body: { 'id' => '19:meeting_abc@thread.v2' })
      allow(graph_conn).to receive(:get).with('chats/19:meeting_abc@thread.v2').and_return(chat_response)

      result = runner.resolve_meeting(chat_thread_id: '19:meeting_abc@thread.v2')
      expect(result[:error]).to eq('chat has no onlineMeetingInfo')
    end

    it 'returns error when chat not found' do
      chat_response = instance_double(Faraday::Response,
                                      body: { 'error' => { 'code' => 'NotFound', 'message' => 'not found' } })
      allow(graph_conn).to receive(:get).with('chats/19:meeting_abc@thread.v2').and_return(chat_response)

      result = runner.resolve_meeting(chat_thread_id: '19:meeting_abc@thread.v2')
      expect(result[:error]).to eq('chat not found')
    end

    it 'resolves a meeting directly from a join URL' do
      meeting_response = instance_double(Faraday::Response,
                                         body: { 'value' => [{ 'id' => 'real-meeting-id', 'subject' => 'Standup' }] })
      allow(graph_conn).to receive(:get)
        .with('me/onlineMeetings', { '$filter' => "joinWebUrl eq 'https://teams.microsoft.com/meet/123'" })
        .and_return(meeting_response)

      result = runner.resolve_meeting(join_url: 'https://teams.microsoft.com/meet/123')
      expect(result[:result]['id']).to eq('real-meeting-id')
    end

    it 'returns error when neither param provided' do
      result = runner.resolve_meeting
      expect(result[:error]).to eq('provide chat_thread_id or join_url')
    end
  end

  describe '#get_attendance_report' do
    it 'retrieves a specific attendance report' do
      response = instance_double(Faraday::Response,
                                 body: { 'id' => 'r1', 'attendanceRecords' => [{ 'identity' => { 'displayName' => 'Alice' } }] })
      allow(graph_conn).to receive(:get).with('users/u1/onlineMeetings/m1/attendanceReports/r1').and_return(response)

      result = runner.get_attendance_report(user_id: 'u1', meeting_id: 'm1', report_id: 'r1')
      expect(result[:result]['attendanceRecords']).not_to be_empty
    end
  end
end
