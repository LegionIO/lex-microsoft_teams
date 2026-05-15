# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/microsoft_teams/helpers/client'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::Client do
  let(:host) { Object.new.extend(described_class) }

  describe '#graph_connection' do
    context 'when token is provided explicitly' do
      it 'builds a Faraday connection with the given token' do
        conn = host.graph_connection(token: 'explicit-token')
        expect(conn).to be_a(Faraday::Connection)
        expect(conn.headers['Authorization']).to eq('Bearer explicit-token')
      end
    end

    context 'when no token is provided' do
      context 'and TokenManager is available' do
        before do
          stub_const('Legion::Extensions::Identity::Entra::Helpers::TokenManager', double)
          allow(Legion::Extensions::Identity::Entra::Helpers::TokenManager)
            .to receive(:load_token).with(:delegated).and_return('test-token')
        end

        it 'fetches the delegated token from entra TokenManager' do
          conn = host.graph_connection
          expect(conn.headers['Authorization']).to eq('Bearer test-token')
        end
      end

      context 'and TokenManager is not available' do
        it 'builds a connection with no Authorization header' do
          conn = host.graph_connection
          expect(conn.headers['Authorization']).to be_nil
        end
      end

      context 'and TokenManager raises an error' do
        before do
          stub_const('Legion::Extensions::Identity::Entra::Helpers::TokenManager', double)
          allow(Legion::Extensions::Identity::Entra::Helpers::TokenManager)
            .to receive(:load_token).with(:delegated).and_raise(StandardError, 'vault unavailable')
        end

        it 'builds a connection with no Authorization header' do
          conn = host.graph_connection
          expect(conn.headers['Authorization']).to be_nil
        end
      end
    end

    it 'uses the default Graph API URL' do
      conn = host.graph_connection(token: 'tok')
      expect(conn.url_prefix.to_s).to start_with('https://graph.microsoft.com/v1.0')
    end

    it 'accepts a custom api_url' do
      conn = host.graph_connection(token: 'tok', api_url: 'https://graph.microsoft.com/beta')
      expect(conn.url_prefix.to_s).to start_with('https://graph.microsoft.com/beta')
    end
  end

  describe '#bot_connection' do
    it 'builds a Faraday connection with the given token' do
      conn = host.bot_connection(token: 'bot-token')
      expect(conn).to be_a(Faraday::Connection)
      expect(conn.headers['Authorization']).to eq('Bearer bot-token')
    end

    it 'builds a connection without Authorization header when no token given' do
      conn = host.bot_connection
      expect(conn.headers['Authorization']).to be_nil
    end

    it 'uses the default Bot Framework service URL' do
      conn = host.bot_connection(token: 'tok')
      expect(conn.url_prefix.to_s).to start_with('https://smba.trafficmanager.net/teams/')
    end
  end

  describe '#user_path' do
    it 'returns me for default' do
      expect(host.user_path).to eq('me')
      expect(host.user_path('me')).to eq('me')
    end

    it 'returns users/<id> for a specific user' do
      expect(host.user_path('user-123')).to eq('users/user-123')
    end
  end

  describe '#oauth_connection' do
    it 'builds a connection to the tenant-specific login endpoint' do
      conn = host.oauth_connection(tenant_id: 'my-tenant')
      expect(conn.url_prefix.to_s).to start_with('https://login.microsoftonline.com/my-tenant')
    end

    it 'defaults to common tenant' do
      conn = host.oauth_connection
      expect(conn.url_prefix.to_s).to start_with('https://login.microsoftonline.com/common')
    end
  end
end
