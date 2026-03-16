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
      allow(oauth_conn).to receive(:post).with('oauth2/v2.0/token', hash_including(
                                                                      grant_type: 'client_credentials'
                                                                    )).and_return(token_response)

      result = runner.acquire_token(tenant_id: 'test-tenant', client_id: 'app-id', client_secret: 'secret')
      expect(result[:result]['access_token']).to eq('eyJ0eXAi...')
    end
  end

  describe '#request_device_code' do
    it 'requests a device code for interactive login' do
      device_response = instance_double(Faraday::Response, body: {
                                          'device_code'      => 'DEVICE123',
                                          'user_code'        => 'ABC-DEF',
                                          'verification_uri' => 'https://microsoft.com/devicelogin',
                                          'expires_in'       => 900,
                                          'interval'         => 5
                                        })
      allow(oauth_conn).to receive(:post).with('oauth2/v2.0/devicecode', hash_including(
                                                                           client_id: 'app-id'
                                                                         )).and_return(device_response)

      result = runner.request_device_code(tenant_id: 'test-tenant', client_id: 'app-id')
      expect(result[:result]['user_code']).to eq('ABC-DEF')
      expect(result[:result]['device_code']).to eq('DEVICE123')
    end
  end

  describe '#poll_device_code' do
    it 'returns token when authorization completes' do
      allow(oauth_conn).to receive(:post).with('oauth2/v2.0/token', hash_including(
                                                                      grant_type: 'urn:ietf:params:oauth:grant-type:device_code'
                                                                    )).and_return(token_response)

      result = runner.poll_device_code(tenant_id: 'test-tenant', client_id: 'app-id', device_code: 'DEVICE123')
      expect(result[:result]['access_token']).to eq('eyJ0eXAi...')
    end

    it 'returns error for denied authorization' do
      error_response = instance_double(Faraday::Response, body: {
                                         'error'             => 'authorization_declined',
                                         'error_description' => 'User denied'
                                       })
      allow(oauth_conn).to receive(:post).and_return(error_response)

      result = runner.poll_device_code(tenant_id: 'test-tenant', client_id: 'app-id', device_code: 'DEVICE123')
      expect(result[:error]).to eq('authorization_declined')
    end
  end

  describe '#acquire_bot_token' do
    it 'requests a bot framework token' do
      allow(oauth_conn).to receive(:post).with('oauth2/v2.0/token', hash_including(
                                                                      scope: 'https://api.botframework.com/.default'
                                                                    )).and_return(token_response)

      result = runner.acquire_bot_token(client_id: 'app-id', client_secret: 'secret')
      expect(result[:result]['token_type']).to eq('Bearer')
    end
  end

  describe '#authorize_url' do
    it 'returns a properly formatted authorization URL' do
      url = runner.authorize_url(
        tenant_id:             'test-tenant',
        client_id:             'app-id',
        redirect_uri:          'http://localhost:12345/callback',
        scope:                 'OnlineMeetings.Read offline_access',
        state:                 'random-state',
        code_challenge:        'challenge123',
        code_challenge_method: 'S256'
      )
      expect(url).to start_with('https://login.microsoftonline.com/test-tenant/oauth2/v2.0/authorize?')
      expect(url).to include('client_id=app-id')
      expect(url).to include('response_type=code')
      expect(url).to include('redirect_uri=http')
      expect(url).to include('scope=OnlineMeetings.Read')
      expect(url).to include('state=random-state')
      expect(url).to include('code_challenge=challenge123')
      expect(url).to include('code_challenge_method=S256')
    end
  end

  describe '#exchange_code' do
    it 'exchanges an authorization code for tokens' do
      allow(oauth_conn).to receive(:post).with('oauth2/v2.0/token', hash_including(
                                                                      grant_type: 'authorization_code'
                                                                    )).and_return(token_response)

      result = runner.exchange_code(
        tenant_id:     'test-tenant',
        client_id:     'app-id',
        code:          'auth-code-123',
        redirect_uri:  'http://localhost:12345/callback',
        code_verifier: 'verifier123'
      )
      expect(result[:result]['access_token']).to eq('eyJ0eXAi...')
    end
  end

  describe '#refresh_delegated_token' do
    it 'exchanges a refresh token for new tokens' do
      allow(oauth_conn).to receive(:post).with('oauth2/v2.0/token', hash_including(
                                                                      grant_type: 'refresh_token'
                                                                    )).and_return(token_response)

      result = runner.refresh_delegated_token(
        tenant_id:     'test-tenant',
        client_id:     'app-id',
        refresh_token: 'refresh-token-123'
      )
      expect(result[:result]['access_token']).to eq('eyJ0eXAi...')
    end
  end
end
