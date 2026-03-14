# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Auth do
  let(:runner) { Object.new.extend(described_class) }
  let(:oauth_conn) { instance_double(Faraday::Connection) }
  let(:token_response) do
    instance_double(Faraday::Response, body: {
                      'access_token' => 'eyJ0eXAi...',
                      'token_type'   => 'Bearer',
                      'expires_in'   => 3600
                    })
  end

  before do
    allow(runner).to receive(:oauth_connection).and_return(oauth_conn)
  end

  describe '#acquire_token' do
    it 'requests a token using client credentials' do
      allow(oauth_conn).to receive(:post).with('/oauth2/v2.0/token', hash_including(
                                                                       grant_type: 'client_credentials'
                                                                     )).and_return(token_response)

      result = runner.acquire_token(tenant_id: 'test-tenant', client_id: 'app-id', client_secret: 'secret')
      expect(result[:result]['access_token']).to eq('eyJ0eXAi...')
    end
  end

  describe '#acquire_bot_token' do
    it 'requests a bot framework token' do
      allow(oauth_conn).to receive(:post).with('/oauth2/v2.0/token', hash_including(
                                                                       scope: 'https://api.botframework.com/.default'
                                                                     )).and_return(token_response)

      result = runner.acquire_bot_token(client_id: 'app-id', client_secret: 'secret')
      expect(result[:result]['token_type']).to eq('Bearer')
    end
  end
end
