# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Client do
  describe '#initialize' do
    it 'stores configuration options' do
      client = described_class.new(tenant_id: 'tenant', client_id: 'app', client_secret: 'secret')
      expect(client.opts[:tenant_id]).to eq('tenant')
      expect(client.opts[:client_id]).to eq('app')
    end
  end

  describe '#authenticate!' do
    it 'acquires a token and stores it in opts' do
      client = described_class.new(tenant_id: 'tenant', client_id: 'app', client_secret: 'secret')
      oauth_conn = instance_double(Faraday::Connection)
      response = instance_double(Faraday::Response, body: { 'access_token' => 'new-token', 'expires_in' => 3600 })

      allow(client).to receive(:oauth_connection).and_return(oauth_conn)
      allow(oauth_conn).to receive(:post).and_return(response)

      client.authenticate!
      expect(client.opts[:token]).to eq('new-token')
    end
  end

  describe 'includes all runner modules' do
    subject(:client) { described_class.new }

    it { is_expected.to respond_to(:acquire_token) }
    it { is_expected.to respond_to(:list_joined_teams) }
    it { is_expected.to respond_to(:list_chats) }
    it { is_expected.to respond_to(:send_chat_message) }
    it { is_expected.to respond_to(:list_channels) }
    it { is_expected.to respond_to(:send_channel_message) }
    it { is_expected.to respond_to(:create_subscription) }
    it { is_expected.to respond_to(:build_card) }
    it { is_expected.to respond_to(:send_activity) }
  end
end
