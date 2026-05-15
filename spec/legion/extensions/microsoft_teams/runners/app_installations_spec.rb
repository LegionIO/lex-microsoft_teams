# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::AppInstallations do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_installed_apps_for_user' do
    it 'lists apps installed for the current user by default' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'inst1' }] })
      allow(graph_conn).to receive(:get)
        .with('me/teamwork/installedApps')
        .and_return(response)

      result = runner.list_installed_apps_for_user
      expect(result[:result]['value'].first['id']).to eq('inst1')
    end

    it 'uses the provided user_id' do
      response = instance_double(Faraday::Response, body: { 'value' => [] })
      allow(graph_conn).to receive(:get)
        .with('users/u1/teamwork/installedApps')
        .and_return(response)

      result = runner.list_installed_apps_for_user(user_id: 'u1')
      expect(result[:result]['value']).to eq([])
    end
  end

  describe '#list_installed_apps_in_chat' do
    it 'lists apps installed in a specific chat' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'inst2' }] })
      allow(graph_conn).to receive(:get)
        .with('chats/ch1/installedApps')
        .and_return(response)

      result = runner.list_installed_apps_in_chat(chat_id: 'ch1')
      expect(result[:result]['value'].first['id']).to eq('inst2')
    end
  end

  describe '#install_app_for_user' do
    it 'installs an app for a user' do
      response = instance_double(Faraday::Response, body: '')
      expected_payload = {
        'teamsApp@odata.bind' => 'https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/app1'
      }
      allow(graph_conn).to receive(:post)
        .with('users/u1/teamwork/installedApps', expected_payload)
        .and_return(response)

      result = runner.install_app_for_user(user_id: 'u1', app_id: 'app1')
      expect(result[:result]).to eq('')
    end

    it 'uses me as default user_id' do
      response = instance_double(Faraday::Response, body: '')
      allow(graph_conn).to receive(:post)
        .with('me/teamwork/installedApps',
              { 'teamsApp@odata.bind' => 'https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/app2' })
        .and_return(response)

      result = runner.install_app_for_user(app_id: 'app2')
      expect(result[:result]).to eq('')
    end
  end

  describe '#uninstall_app_for_user' do
    it 'uninstalls an app for a user' do
      response = instance_double(Faraday::Response, body: '')
      allow(graph_conn).to receive(:delete)
        .with('users/u1/teamwork/installedApps/inst1')
        .and_return(response)

      result = runner.uninstall_app_for_user(user_id: 'u1', installation_id: 'inst1')
      expect(result[:result]).to eq('')
    end

    it 'uses me as default user_id' do
      response = instance_double(Faraday::Response, body: '')
      allow(graph_conn).to receive(:delete)
        .with('me/teamwork/installedApps/inst2')
        .and_return(response)

      result = runner.uninstall_app_for_user(installation_id: 'inst2')
      expect(result[:result]).to eq('')
    end
  end
end
