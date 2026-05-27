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

  describe 'middleware wiring' do
    def middleware_classes(conn)
      # Faraday 2.x exposes the builder via #builder; the handlers array
      # holds Faraday::MiddlewareRegistry entries whose #klass returns the
      # class. Works for connections built via both graph_connection and
      # bot_connection.
      conn.builder.handlers.map(&:klass)
    end

    it 'wires RetryAfter into the graph_connection middleware stack' do
      conn = host.graph_connection(token: 'tok')

      expect(middleware_classes(conn)).to include(
        Legion::Extensions::MicrosoftTeams::Faraday::RetryAfter
      )
    end

    it 'wires RetryAfter into the bot_connection middleware stack' do
      conn = host.bot_connection(token: 'tok')

      expect(middleware_classes(conn)).to include(
        Legion::Extensions::MicrosoftTeams::Faraday::RetryAfter
      )
    end

    it 'does not wire RetryAfter into oauth_connection (login endpoint is not retry-on-429)' do
      conn = host.oauth_connection(tenant_id: 'common')

      expect(middleware_classes(conn)).not_to include(
        Legion::Extensions::MicrosoftTeams::Faraday::RetryAfter
      )
    end
  end

  describe 'retry settings plumbing' do
    let(:host_with_settings_class) do
      Class.new do
        include Legion::Extensions::MicrosoftTeams::Helpers::Client

        attr_writer :_settings

        def settings
          @_settings || {}
        end
      end
    end

    let(:settings_host) { host_with_settings_class.new }

    it 'honors falsey settings values like max_retries: 0 instead of silently defaulting' do
      settings_host._settings = { client: { retry: { max_retries: 0 } } }
      opts = settings_host.send(:retry_after_options)

      expect(opts[:max_retries]).to eq(0)
    end

    it 'uses defaults when no settings are configured' do
      opts = settings_host.send(:retry_after_options)

      expect(opts[:max_retries]).to eq(3)
      expect(opts[:max_wait]).to eq(60.0)
      expect(opts[:jitter]).to eq(0.2)
      expect(opts[:fallback_wait]).to eq(1.0)
      expect(opts[:retry_statuses]).to eq([429])
    end

    it 'plumbs retry_statuses through settings' do
      settings_host._settings = { client: { retry: { retry_statuses: [429, 503] } } }
      opts = settings_host.send(:retry_after_options)

      expect(opts[:retry_statuses]).to eq([429, 503])
    end

    it 'accepts string keys for backward compatibility' do
      settings_host._settings = { 'client' => { 'retry' => { 'max_retries' => 7, 'jitter' => 0.5 } } }
      opts = settings_host.send(:retry_after_options)

      expect(opts[:max_retries]).to eq(7)
      expect(opts[:jitter]).to eq(0.5)
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
