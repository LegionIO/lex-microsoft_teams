# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Activities do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_activity_feed' do
    it 'lists installed apps (activity feed) for the current user' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'app1' }] })
      allow(graph_conn).to receive(:get)
        .with('me/teamwork/installedApps', { '$top' => 50 })
        .and_return(response)

      result = runner.list_activity_feed
      expect(result[:result]['value'].first['id']).to eq('app1')
    end

    it 'accepts a custom user_id and top' do
      response = instance_double(Faraday::Response, body: { 'value' => [] })
      allow(graph_conn).to receive(:get)
        .with('users/u1/teamwork/installedApps', { '$top' => 10 })
        .and_return(response)

      result = runner.list_activity_feed(user_id: 'u1', top: 10)
      expect(result[:result]['value']).to eq([])
    end
  end

  describe '#send_activity_notification' do
    let(:topic) { { source: 'entityUrl', value: 'https://graph.microsoft.com/v1.0/teams/t1' } }

    it 'sends an activity notification without preview_text' do
      response = instance_double(Faraday::Response, body: '')
      allow(graph_conn).to receive(:post)
        .with('users/u1/teamwork/sendActivityNotification',
              { topic: topic, activityType: 'taskCreated' })
        .and_return(response)

      result = runner.send_activity_notification(user_id: 'u1', topic: topic, activity_type: 'taskCreated')
      expect(result[:result]).to eq('')
    end

    it 'includes previewText when provided' do
      response = instance_double(Faraday::Response, body: '')
      preview = { content: 'A new task was assigned to you' }
      allow(graph_conn).to receive(:post)
        .with('users/u1/teamwork/sendActivityNotification',
              { topic: topic, activityType: 'taskCreated', previewText: preview })
        .and_return(response)

      result = runner.send_activity_notification(
        user_id: 'u1', topic: topic, activity_type: 'taskCreated', preview_text: preview
      )
      expect(result[:result]).to eq('')
    end
  end
end
