# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Activities do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#send_activity_notification' do
    let(:topic) { { source: 'entityUrl', value: 'https://graph.microsoft.com/v1.0/teams/t1' } }

    it 'sends an activity notification to a specific user without preview_text' do
      response = instance_double(Faraday::Response, body: '')
      allow(graph_conn).to receive(:post)
        .with('users/u1/teamwork/sendActivityNotification',
              { topic: topic, activityType: 'taskCreated' })
        .and_return(response)

      result = runner.send_activity_notification(user_id: 'u1', topic: topic, activity_type: 'taskCreated')
      expect(result[:result]).to eq('')
    end

    it 'defaults user_id to me' do
      response = instance_double(Faraday::Response, body: '')
      allow(graph_conn).to receive(:post)
        .with('me/teamwork/sendActivityNotification',
              { topic: topic, activityType: 'taskCreated' })
        .and_return(response)

      result = runner.send_activity_notification(topic: topic, activity_type: 'taskCreated')
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
