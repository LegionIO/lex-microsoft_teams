# Delegated OAuth Browser Flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add browser-based delegated OAuth (Auth Code + PKCE with Device Code fallback) to lex-microsoft_teams so users can authenticate with their own Microsoft account.

**Architecture:** New `BrowserAuth` orchestrator detects headless vs GUI, opens browser for Auth Code + PKCE or falls back to Device Code. Ephemeral TCPServer for CLI, Sinatra route for daemon. Tokens stored in Vault via `Legion::Crypt`, cached in-memory by `TokenCache`. Silent refresh before expiry, re-auth only when refresh_token expires.

**Tech Stack:** Ruby stdlib (`socket`, `securerandom`, `digest`, `base64`, `uri`, `cgi`, `rbconfig`), Faraday, legion-crypt (Vault KV v2), Sinatra (existing API)

---

### Task 1: Add `authorize_url` and `exchange_code` to Runners::Auth

These are the two new runner methods for the Authorization Code + PKCE flow: building the authorize URL and exchanging the code for tokens.

**Files:**
- Modify: `lib/legion/extensions/microsoft_teams/runners/auth.rb`
- Modify: `spec/legion/extensions/microsoft_teams/runners/auth_spec.rb`

**Step 1: Write the failing tests**

Add these tests to the existing `auth_spec.rb`:

```ruby
describe '#authorize_url' do
  it 'returns a properly formatted authorization URL' do
    url = runner.authorize_url(
      tenant_id: 'test-tenant',
      client_id: 'app-id',
      redirect_uri: 'http://localhost:12345/callback',
      scope: 'OnlineMeetings.Read offline_access',
      state: 'random-state',
      code_challenge: 'challenge123',
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
      tenant_id: 'test-tenant',
      client_id: 'app-id',
      code: 'auth-code-123',
      redirect_uri: 'http://localhost:12345/callback',
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
      tenant_id: 'test-tenant',
      client_id: 'app-id',
      refresh_token: 'refresh-token-123'
    )
    expect(result[:result]['access_token']).to eq('eyJ0eXAi...')
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/runners/auth_spec.rb -v`
Expected: FAIL with `NoMethodError: undefined method 'authorize_url'`

**Step 3: Write the implementation**

Add these methods to `Runners::Auth` module (before the `include Helpers::Lex` guard at the bottom):

```ruby
def authorize_url(tenant_id:, client_id:, redirect_uri:, scope:, state:,
                  code_challenge:, code_challenge_method: 'S256', **)
  require 'uri'
  params = URI.encode_www_form(
    client_id:             client_id,
    response_type:         'code',
    redirect_uri:          redirect_uri,
    scope:                 scope,
    state:                 state,
    code_challenge:        code_challenge,
    code_challenge_method: code_challenge_method
  )
  "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/authorize?#{params}"
end

def exchange_code(tenant_id:, client_id:, code:, redirect_uri:, code_verifier:,
                  scope: 'OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access', **)
  response = oauth_connection(tenant_id: tenant_id).post('oauth2/v2.0/token', {
                                                            grant_type:    'authorization_code',
                                                            client_id:     client_id,
                                                            code:          code,
                                                            redirect_uri:  redirect_uri,
                                                            code_verifier: code_verifier,
                                                            scope:         scope
                                                          })
  { result: response.body }
end

def refresh_delegated_token(tenant_id:, client_id:, refresh_token:,
                            scope: 'OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access', **)
  response = oauth_connection(tenant_id: tenant_id).post('oauth2/v2.0/token', {
                                                            grant_type:    'refresh_token',
                                                            client_id:     client_id,
                                                            refresh_token: refresh_token,
                                                            scope:         scope
                                                          })
  { result: response.body }
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/runners/auth_spec.rb -v`
Expected: All PASS

**Step 5: Run full suite + rubocop**

Run: `bundle exec rspec && bundle exec rubocop`

**Step 6: Commit**

```bash
git add lib/legion/extensions/microsoft_teams/runners/auth.rb spec/legion/extensions/microsoft_teams/runners/auth_spec.rb
git commit -m "add authorize_url, exchange_code, and refresh_delegated_token to auth runner"
```

---

### Task 2: Create Helpers::CallbackServer

An ephemeral TCP server bound to localhost that receives the OAuth callback, extracts the `code` and `state` parameters, sends back a "close this window" HTML page, and shuts down.

**Files:**
- Create: `lib/legion/extensions/microsoft_teams/helpers/callback_server.rb`
- Create: `spec/legion/extensions/microsoft_teams/helpers/callback_server_spec.rb`

**Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true

require 'net/http'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::CallbackServer do
  describe '#start and #wait_for_callback' do
    it 'returns the port it is listening on' do
      server = described_class.new
      server.start
      expect(server.port).to be_a(Integer)
      expect(server.port).to be > 0
      server.shutdown
    end

    it 'captures code and state from the callback request' do
      server = described_class.new
      server.start

      # Simulate the browser redirect in a thread
      Thread.new do
        sleep(0.1)
        Net::HTTP.get(URI("http://127.0.0.1:#{server.port}/callback?code=AUTH_CODE_123&state=STATE_ABC"))
      end

      result = server.wait_for_callback(timeout: 5)
      expect(result[:code]).to eq('AUTH_CODE_123')
      expect(result[:state]).to eq('STATE_ABC')
      server.shutdown
    end

    it 'returns nil on timeout' do
      server = described_class.new
      server.start
      result = server.wait_for_callback(timeout: 1)
      expect(result).to be_nil
      server.shutdown
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/helpers/callback_server_spec.rb -v`
Expected: FAIL with `NameError: uninitialized constant`

**Step 3: Write the implementation**

```ruby
# frozen_string_literal: true

require 'socket'
require 'cgi'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        class CallbackServer
          RESPONSE_HTML = <<~HTML
            <html><body style="font-family:sans-serif;text-align:center;padding:40px;">
            <h2>Authentication complete</h2><p>You can close this window.</p></body></html>
          HTML

          attr_reader :port

          def initialize
            @server = nil
            @port = nil
            @result = nil
            @mutex = Mutex.new
            @cv = ConditionVariable.new
          end

          def start
            @server = TCPServer.new('127.0.0.1', 0)
            @port = @server.addr[1]
            @thread = Thread.new { listen }
          end

          def wait_for_callback(timeout: 120)
            @mutex.synchronize do
              @cv.wait(@mutex, timeout) unless @result
              @result
            end
          end

          def shutdown
            @server&.close rescue nil # rubocop:disable Style/RescueModifier
            @thread&.kill
          end

          def redirect_uri
            "http://localhost:#{@port}/callback"
          end

          private

          def listen
            loop do
              client = @server.accept
              request_line = client.gets
              # drain headers
              nil until client.gets&.strip&.empty?

              if request_line&.include?('/callback?')
                query = request_line.split(' ')[1].split('?', 2).last
                params = CGI.parse(query)

                @mutex.synchronize do
                  @result = {
                    code:  params['code']&.first,
                    state: params['state']&.first
                  }
                  @cv.broadcast
                end
              end

              client.print "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n#{RESPONSE_HTML}"
              client.close
              break if @result
            end
          rescue IOError
            nil # server closed
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/helpers/callback_server_spec.rb -v`
Expected: All PASS

**Step 5: Run rubocop**

Run: `bundle exec rubocop lib/legion/extensions/microsoft_teams/helpers/callback_server.rb`

**Step 6: Commit**

```bash
git add lib/legion/extensions/microsoft_teams/helpers/callback_server.rb spec/legion/extensions/microsoft_teams/helpers/callback_server_spec.rb
git commit -m "add ephemeral callback server for oauth redirect"
```

---

### Task 3: Create Helpers::BrowserAuth

The orchestrator that ties everything together: generates PKCE, detects headless, opens browser or falls back to device code, waits for callback, exchanges code, stores tokens in Vault.

**Files:**
- Create: `lib/legion/extensions/microsoft_teams/helpers/browser_auth.rb`
- Create: `spec/legion/extensions/microsoft_teams/helpers/browser_auth_spec.rb`

**Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth do
  let(:auth_runner) { Object.new.extend(Legion::Extensions::MicrosoftTeams::Runners::Auth) }
  let(:browser_auth) do
    described_class.new(
      tenant_id: 'test-tenant',
      client_id: 'app-id',
      scopes:    'OnlineMeetings.Read offline_access',
      auth:      auth_runner
    )
  end

  describe '#generate_pkce' do
    it 'returns a verifier and challenge pair' do
      verifier, challenge = browser_auth.generate_pkce
      expect(verifier).to be_a(String)
      expect(verifier.length).to be >= 43
      expect(challenge).to be_a(String)
      expect(challenge).not_to eq(verifier)
    end

    it 'generates a valid S256 challenge' do
      require 'digest'
      require 'base64'
      verifier, challenge = browser_auth.generate_pkce
      expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      expect(challenge).to eq(expected)
    end
  end

  describe '#gui_available?' do
    it 'returns true on macOS' do
      allow(browser_auth).to receive(:host_os).and_return('darwin22')
      expect(browser_auth.gui_available?).to be true
    end

    it 'returns false on Linux without DISPLAY' do
      allow(browser_auth).to receive(:host_os).and_return('linux-gnu')
      allow(ENV).to receive(:[]).with('DISPLAY').and_return(nil)
      allow(ENV).to receive(:[]).with('WAYLAND_DISPLAY').and_return(nil)
      expect(browser_auth.gui_available?).to be false
    end

    it 'returns true on Linux with DISPLAY' do
      allow(browser_auth).to receive(:host_os).and_return('linux-gnu')
      allow(ENV).to receive(:[]).with('DISPLAY').and_return(':0')
      expect(browser_auth.gui_available?).to be true
    end
  end

  describe '#open_browser' do
    it 'calls system open on macOS' do
      allow(browser_auth).to receive(:host_os).and_return('darwin22')
      allow(browser_auth).to receive(:system).and_return(true)
      expect(browser_auth.open_browser('https://example.com')).to be true
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/helpers/browser_auth_spec.rb -v`
Expected: FAIL with `NameError: uninitialized constant`

**Step 3: Write the implementation**

```ruby
# frozen_string_literal: true

require 'securerandom'
require 'digest'
require 'base64'
require 'rbconfig'

require 'legion/extensions/microsoft_teams/runners/auth'
require 'legion/extensions/microsoft_teams/helpers/callback_server'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        class BrowserAuth
          DEFAULT_SCOPES = 'OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access'

          attr_reader :tenant_id, :client_id, :scopes

          def initialize(tenant_id:, client_id:, scopes: DEFAULT_SCOPES, auth: nil)
            @tenant_id = tenant_id
            @client_id = client_id
            @scopes    = scopes
            @auth      = auth || Object.new.extend(Runners::Auth)
          end

          def authenticate
            if gui_available?
              authenticate_browser
            else
              authenticate_device_code
            end
          end

          def generate_pkce
            verifier  = SecureRandom.urlsafe_base64(32)
            challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
            [verifier, challenge]
          end

          def gui_available?
            os = host_os
            return true if os =~ /darwin|mswin|mingw/

            !ENV['DISPLAY'].nil? || !ENV['WAYLAND_DISPLAY'].nil?
          end

          def open_browser(url)
            cmd = case host_os
                  when /darwin/  then 'open'
                  when /linux/   then 'xdg-open'
                  when /mswin|mingw/ then 'start'
                  end
            return false unless cmd

            system(cmd, url)
          end

          private

          def host_os
            RbConfig::CONFIG['host_os']
          end

          def authenticate_browser
            verifier, challenge = generate_pkce
            state = SecureRandom.hex(32)

            server = CallbackServer.new
            server.start

            url = @auth.authorize_url(
              tenant_id:      tenant_id,
              client_id:      client_id,
              redirect_uri:   server.redirect_uri,
              scope:          scopes,
              state:          state,
              code_challenge: challenge
            )

            log_info("Opening browser for authentication...")
            unless open_browser(url)
              log_info("Could not open browser. Falling back to device code flow.")
              server.shutdown
              return authenticate_device_code
            end

            result = server.wait_for_callback(timeout: 120)
            server.shutdown

            unless result && result[:code]
              return { error: 'timeout', description: 'No callback received within timeout' }
            end

            unless result[:state] == state
              return { error: 'state_mismatch', description: 'CSRF state parameter mismatch' }
            end

            @auth.exchange_code(
              tenant_id:     tenant_id,
              client_id:     client_id,
              code:          result[:code],
              redirect_uri:  server.redirect_uri,
              code_verifier: verifier,
              scope:         scopes
            )
          end

          def authenticate_device_code
            dc = @auth.request_device_code(
              tenant_id: tenant_id,
              client_id: client_id,
              scope:     scopes
            )
            body = dc[:result]

            log_info("Go to:  #{body['verification_uri']}")
            log_info("Code:   #{body['user_code']}")

            open_browser(body['verification_uri']) if gui_available?

            @auth.poll_device_code(
              tenant_id:   tenant_id,
              client_id:   client_id,
              device_code: body['device_code']
            )
          end

          def log_info(msg)
            if defined?(Legion::Logging)
              Legion::Logging.info(msg)
            else
              $stdout.puts(msg)
            end
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/helpers/browser_auth_spec.rb -v`
Expected: All PASS

**Step 5: Run rubocop**

Run: `bundle exec rubocop lib/legion/extensions/microsoft_teams/helpers/browser_auth.rb`

**Step 6: Commit**

```bash
git add lib/legion/extensions/microsoft_teams/helpers/browser_auth.rb spec/legion/extensions/microsoft_teams/helpers/browser_auth_spec.rb
git commit -m "add browser auth orchestrator with pkce and device code fallback"
```

---

### Task 4: Extend TokenCache with Delegated Token Support

Add a second token slot for delegated tokens, Vault read/write for persistence, and silent refresh using `refresh_delegated_token`.

**Files:**
- Modify: `lib/legion/extensions/microsoft_teams/helpers/token_cache.rb`
- Modify: `spec/legion/extensions/microsoft_teams/helpers/token_cache_spec.rb` (or create if it doesn't exist)

**Step 1: Write the failing tests**

Create or extend the spec file:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::TokenCache do
  let(:cache) { described_class.new }

  describe '#cached_delegated_token' do
    it 'returns nil when no delegated token is cached' do
      expect(cache.cached_delegated_token).to be_nil
    end

    it 'returns the cached delegated token' do
      cache.store_delegated_token(
        access_token:  'delegated-token-123',
        refresh_token: 'refresh-123',
        expires_in:    3600,
        scopes:        'OnlineMeetings.Read'
      )
      expect(cache.cached_delegated_token).to eq('delegated-token-123')
    end

    it 'returns nil when the delegated token is expired and refresh fails' do
      cache.store_delegated_token(
        access_token:  'old-token',
        refresh_token: 'refresh-123',
        expires_in:    -1, # already expired
        scopes:        'OnlineMeetings.Read'
      )
      # No auth settings available, refresh will fail
      expect(cache.cached_delegated_token).to be_nil
    end
  end

  describe '#store_delegated_token' do
    it 'stores token data in memory' do
      cache.store_delegated_token(
        access_token:  'token-abc',
        refresh_token: 'refresh-abc',
        expires_in:    3600,
        scopes:        'scope1'
      )
      expect(cache.cached_delegated_token).to eq('token-abc')
    end
  end

  describe '#clear_delegated_token!' do
    it 'clears the delegated token cache' do
      cache.store_delegated_token(
        access_token:  'token-abc',
        refresh_token: 'refresh-abc',
        expires_in:    3600,
        scopes:        'scope1'
      )
      cache.clear_delegated_token!
      expect(cache.cached_delegated_token).to be_nil
    end
  end

  describe '#load_from_vault' do
    it 'returns false when Legion::Crypt is not defined' do
      expect(cache.load_from_vault).to be false
    end
  end

  describe '#save_to_vault' do
    it 'returns false when Legion::Crypt is not defined' do
      cache.store_delegated_token(
        access_token:  'token-abc',
        refresh_token: 'refresh-abc',
        expires_in:    3600,
        scopes:        'scope1'
      )
      expect(cache.save_to_vault).to be false
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/helpers/token_cache_spec.rb -v`
Expected: FAIL with `NoMethodError: undefined method 'cached_delegated_token'`

**Step 3: Write the implementation**

Replace `token_cache.rb` with:

```ruby
# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/runners/auth'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        class TokenCache
          REFRESH_BUFFER = 60
          DEFAULT_VAULT_PATH = 'legionio/microsoft_teams/delegated_token'

          def initialize
            @token_cache = nil
            @delegated_cache = nil
            @mutex = Mutex.new
          end

          # --- Application token (client_credentials) ---

          def cached_graph_token
            @mutex.synchronize do
              return @token_cache[:token] if @token_cache && !token_expired?(@token_cache)

              refresh_app_token
            end
          end

          def clear_token_cache!
            @mutex.synchronize { @token_cache = nil }
          end

          # --- Delegated token (user auth) ---

          def cached_delegated_token
            @mutex.synchronize do
              return nil unless @delegated_cache

              return @delegated_cache[:token] unless token_expired?(@delegated_cache)

              refresh_delegated
            end
          end

          def store_delegated_token(access_token:, refresh_token:, expires_in:, scopes:)
            @mutex.synchronize do
              @delegated_cache = {
                token:         access_token,
                refresh_token: refresh_token,
                expires_at:    Time.now + expires_in.to_i,
                scopes:        scopes
              }
            end
          end

          def clear_delegated_token!
            @mutex.synchronize { @delegated_cache = nil }
          end

          def load_from_vault
            return false unless defined?(Legion::Crypt)

            data = Legion::Crypt.get(vault_path)
            return false unless data && data[:access_token]

            @mutex.synchronize do
              @delegated_cache = {
                token:         data[:access_token],
                refresh_token: data[:refresh_token],
                expires_at:    Time.parse(data[:expires_at]),
                scopes:        data[:scopes]
              }
            end
            true
          rescue StandardError => e
            log_error("Failed to load delegated token from Vault: #{e.message}")
            false
          end

          def save_to_vault
            return false unless defined?(Legion::Crypt)

            data = @mutex.synchronize { @delegated_cache&.dup }
            return false unless data

            Legion::Crypt.write(vault_path,
                                access_token:  data[:token],
                                refresh_token: data[:refresh_token],
                                expires_at:    data[:expires_at].utc.iso8601,
                                scopes:        data[:scopes])
            true
          rescue StandardError => e
            log_error("Failed to save delegated token to Vault: #{e.message}")
            false
          end

          private

          def token_expired?(cache_entry)
            return true unless cache_entry

            buffer = delegated_refresh_buffer
            Time.now >= (cache_entry[:expires_at] - buffer)
          end

          def delegated_refresh_buffer
            settings = teams_auth_settings
            delegated = settings[:delegated]
            return REFRESH_BUFFER unless delegated.is_a?(Hash)

            delegated[:refresh_buffer] || REFRESH_BUFFER
          end

          def vault_path
            settings = teams_auth_settings
            delegated = settings[:delegated]
            return DEFAULT_VAULT_PATH unless delegated.is_a?(Hash)

            delegated[:vault_path] || DEFAULT_VAULT_PATH
          end

          def refresh_app_token
            result = acquire_fresh_token
            return nil unless result

            access_token = result.dig(:result, 'access_token')
            expires_in = result.dig(:result, 'expires_in') || 3600

            @token_cache = {
              token:      access_token,
              expires_at: Time.now + expires_in
            }

            access_token
          rescue StandardError => e
            log_error("TokenCache app refresh failed: #{e.message}")
            nil
          end

          def refresh_delegated
            return nil unless @delegated_cache&.dig(:refresh_token)

            settings = teams_auth_settings
            return nil unless settings[:tenant_id] && settings[:client_id]

            auth = Object.new.extend(Legion::Extensions::MicrosoftTeams::Runners::Auth)
            result = auth.refresh_delegated_token(
              tenant_id:     settings[:tenant_id],
              client_id:     settings[:client_id],
              refresh_token: @delegated_cache[:refresh_token],
              scope:         @delegated_cache[:scopes]
            )

            body = result[:result]
            return handle_refresh_failure(result) unless body&.dig('access_token')

            @delegated_cache = {
              token:         body['access_token'],
              refresh_token: body['refresh_token'] || @delegated_cache[:refresh_token],
              expires_at:    Time.now + (body['expires_in'] || 3600).to_i,
              scopes:        @delegated_cache[:scopes]
            }

            save_to_vault
            @delegated_cache[:token]
          rescue StandardError => e
            log_error("TokenCache delegated refresh failed: #{e.message}")
            nil
          end

          def handle_refresh_failure(result)
            if result[:error] == 'invalid_grant'
              @delegated_cache = nil
              emit_expired_event
            end
            nil
          end

          def emit_expired_event
            Legion::Events.emit('microsoft_teams.auth.expired') if defined?(Legion::Events)
          end

          def acquire_fresh_token
            settings = teams_auth_settings
            return nil unless settings[:tenant_id] && settings[:client_id] && settings[:client_secret]

            auth = Object.new.extend(Legion::Extensions::MicrosoftTeams::Runners::Auth)
            auth.acquire_token(
              tenant_id:     settings[:tenant_id],
              client_id:     settings[:client_id],
              client_secret: settings[:client_secret]
            )
          end

          def teams_auth_settings
            return {} unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :auth) || {}
          end

          def log_error(msg)
            Legion::Logging.error(msg) if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/legion/extensions/microsoft_teams/helpers/token_cache_spec.rb -v`
Expected: All PASS

**Step 5: Run full suite + rubocop**

Run: `bundle exec rspec && bundle exec rubocop`

**Step 6: Commit**

```bash
git add lib/legion/extensions/microsoft_teams/helpers/token_cache.rb spec/legion/extensions/microsoft_teams/helpers/token_cache_spec.rb
git commit -m "extend token cache with delegated token support and vault persistence"
```

---

### Task 5: Wire BrowserAuth and CallbackServer into Entry Point

Register the new helpers in the extension entry point so they're available.

**Files:**
- Modify: `lib/legion/extensions/microsoft_teams.rb`

**Step 1: Add the requires**

After the existing helper requires (line 25 area), add:

```ruby
require 'legion/extensions/microsoft_teams/helpers/callback_server'
require 'legion/extensions/microsoft_teams/helpers/browser_auth'
```

**Step 2: Run full suite**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: All PASS, zero offenses

**Step 3: Commit**

```bash
git add lib/legion/extensions/microsoft_teams.rb
git commit -m "wire browser auth and callback server into extension entry point"
```

---

### Task 6: Add `legion auth` CLI Command to LegionIO

Add a new Thor subcommand `legion auth teams` that triggers `BrowserAuth` for interactive authentication.

**Files:**
- Create: `lib/legion/cli/auth_command.rb` (in the LegionIO repo)
- Modify: `lib/legion/cli.rb` (in the LegionIO repo)

**Important context:** The LegionIO repo is at `/Users/miverso2/rubymine/legion/LegionIO/`. The CLI pattern uses Thor subcommands. See `doctor_command.rb` for the pattern.

**Step 1: Create the auth command**

```ruby
# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Auth < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'teams', 'Authenticate with Microsoft Teams using your browser'
      method_option :tenant_id,  type: :string, desc: 'Azure AD tenant ID'
      method_option :client_id,  type: :string, desc: 'Entra application client ID'
      method_option :scopes,     type: :string, desc: 'OAuth scopes to request'
      def teams
        out = formatter
        require 'legion/settings'
        Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)

        auth_settings = Legion::Settings.dig(:microsoft_teams, :auth) || {}
        delegated = auth_settings[:delegated] || {}

        tenant_id = options[:tenant_id] || auth_settings[:tenant_id]
        client_id = options[:client_id] || auth_settings[:client_id]
        scopes    = options[:scopes] || delegated[:scopes] ||
                    'OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access'

        unless tenant_id && client_id
          out.error('Missing tenant_id or client_id. Set in settings or pass --tenant-id and --client-id')
          raise SystemExit, 1
        end

        require 'legion/extensions/microsoft_teams/helpers/browser_auth'
        browser_auth = Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth.new(
          tenant_id: tenant_id,
          client_id: client_id,
          scopes:    scopes
        )

        out.header('Microsoft Teams Authentication')
        result = browser_auth.authenticate

        if result[:error]
          out.error("Authentication failed: #{result[:error]} - #{result[:description]}")
          raise SystemExit, 1
        end

        body = result[:result]
        out.success('Authentication successful!')

        # Store in TokenCache and Vault
        require 'legion/extensions/microsoft_teams/helpers/token_cache'
        cache = Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.new
        cache.store_delegated_token(
          access_token:  body['access_token'],
          refresh_token: body['refresh_token'],
          expires_in:    body['expires_in'] || 3600,
          scopes:        scopes
        )

        if cache.save_to_vault
          out.success('Token saved to Vault')
        else
          out.warn('Could not save token to Vault (Vault may not be connected)')
        end

        if options[:json]
          out.json({ authenticated: true, scopes: scopes, expires_in: body['expires_in'] })
        end
      end

      default_task :teams

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end
      end
    end
  end
end
```

**Step 2: Register in CLI::Main**

In `lib/legion/cli.rb`, add the autoload (after the existing autoloads, around line 34):

```ruby
autoload :Auth,       'legion/cli/auth_command'
```

And register the subcommand (after the existing subcommands, around line 191):

```ruby
desc 'auth SUBCOMMAND', 'Authenticate with external services'
subcommand 'auth', Legion::CLI::Auth
```

**Step 3: Run LegionIO tests**

Run: `cd /Users/miverso2/rubymine/legion/LegionIO && bundle exec rspec && bundle exec rubocop`
Expected: All PASS

**Step 4: Commit (in LegionIO repo)**

```bash
cd /Users/miverso2/rubymine/legion/LegionIO
git add lib/legion/cli/auth_command.rb lib/legion/cli.rb
git commit -m "add legion auth teams cli command for delegated oauth"
```

---

### Task 7: Add OAuth Callback Sinatra Route to LegionIO API

Add `GET /api/oauth/microsoft_teams/callback` for daemon-initiated re-auth.

**Files:**
- Create: `lib/legion/api/oauth.rb` (in the LegionIO repo)
- Modify: `lib/legion/api.rb` (in the LegionIO repo)

**Step 1: Create the route module**

```ruby
# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module OAuth
        def self.registered(app)
          register_callback(app)
        end

        def self.register_callback(app)
          app.get '/api/oauth/microsoft_teams/callback' do
            content_type :html
            code  = params['code']
            state = params['state']

            unless code && state
              status 400
              return '<html><body><h2>Missing code or state parameter</h2></body></html>'
            end

            Legion::Events.emit('microsoft_teams.oauth.callback', code: code, state: state)

            <<~HTML
              <html><body style="font-family:sans-serif;text-align:center;padding:40px;">
              <h2>Authentication complete</h2>
              <p>You can close this window.</p>
              </body></html>
            HTML
          end
        end

        class << self
          private :register_callback
        end
      end
    end
  end
end
```

**Step 2: Register in API**

In `lib/legion/api.rb`, add:

After the require block (around line 22):
```ruby
require_relative 'api/oauth'
```

In the route registration block (around line 86):
```ruby
register Routes::OAuth
```

**Step 3: Run LegionIO tests**

Run: `cd /Users/miverso2/rubymine/legion/LegionIO && bundle exec rspec && bundle exec rubocop`

**Step 4: Commit**

```bash
cd /Users/miverso2/rubymine/legion/LegionIO
git add lib/legion/api/oauth.rb lib/legion/api.rb
git commit -m "add oauth callback sinatra route for daemon re-auth"
```

---

### Task 8: Version Bump, Docs, and Final Push

Update version, CHANGELOG, README, CLAUDE.md, run full pipeline, push.

**Files:**
- Modify: `lib/legion/extensions/microsoft_teams/version.rb` — bump to 0.5.0
- Modify: `CHANGELOG.md` — add v0.5.0 entry
- Modify: `README.md` — add delegated auth section
- Modify: `CLAUDE.md` — update architecture diagram, add BrowserAuth/CallbackServer to helpers

**Step 1: Bump version**

In `version.rb`, change `VERSION = '0.4.1'` to `VERSION = '0.5.0'`.

**Step 2: Update CHANGELOG**

Add under `## [Unreleased]` or create `## [0.5.0]`:

```markdown
## [0.5.0] - 2026-03-16

### Added
- Delegated OAuth browser flow with Authorization Code + PKCE
- Automatic Device Code fallback for headless environments
- `Helpers::BrowserAuth` orchestrator with PKCE, headless detection, browser opening
- `Helpers::CallbackServer` ephemeral TCP server for OAuth redirect
- `Runners::Auth#authorize_url`, `#exchange_code`, `#refresh_delegated_token`
- `Helpers::TokenCache` delegated token slot with Vault persistence and silent refresh
- `legion auth teams` CLI command for interactive authentication
- `GET /api/oauth/microsoft_teams/callback` Sinatra route for daemon re-auth
```

**Step 3: Run full pipeline**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: All PASS, zero offenses

**Step 4: Commit and push**

```bash
git add -A
git commit -m "add delegated oauth browser flow with pkce and device code fallback"
```

Then follow pre-push pipeline (rspec + rubocop verified above) and push:

```bash
git push # pipeline-complete
```

Also push LegionIO changes:

```bash
cd /Users/miverso2/rubymine/legion/LegionIO
git push # pipeline-complete
```
