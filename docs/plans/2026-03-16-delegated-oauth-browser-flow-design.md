# Delegated OAuth Browser Flow Design

## Goal

Add browser-based delegated OAuth authentication to lex-microsoft_teams so users can authenticate with their own Microsoft account for Graph API access. Authorization Code + PKCE as the primary flow, Device Code as the automatic fallback for headless environments.

## Architecture

Opt-in delegated auth: user explicitly triggers via `legion auth teams` CLI command, a bot command (`auth`/`login`), or by enabling `microsoft_teams.auth.delegated.enabled` in settings. Once authenticated, tokens refresh silently. Browser re-opens only when the refresh_token is expired/revoked.

Two callback server paths: ephemeral TCPServer for CLI (works without daemon), Sinatra route on the existing API (port 4567) for daemon-initiated re-auth.

Tokens stored in HashiCorp Vault via legion-crypt. In-memory cache in TokenCache for fast access.

## Components

### New Files

| Component | File | Purpose |
|-----------|------|---------|
| `Helpers::BrowserAuth` | `helpers/browser_auth.rb` | Orchestrator: PKCE generation, headless detection, browser opening, flow selection (Auth Code vs Device Code) |
| `Helpers::CallbackServer` | `helpers/callback_server.rb` | Ephemeral TCPServer on random port, localhost only, receives `?code=&state=`, shuts down after |

### Modified Files

| Component | File | Changes |
|-----------|------|---------|
| `Runners::Auth` | `runners/auth.rb` | Add `authorize_url`, `exchange_code`, `refresh_delegated_token` methods |
| `Helpers::TokenCache` | `helpers/token_cache.rb` | Add delegated token slot, refresh_token support, Vault read/write |

### External Files (LegionIO main repo)

| Component | File | Purpose |
|-----------|------|---------|
| `API::Routes::OAuthCallback` | `api/routes/oauth_callback.rb` | `GET /api/oauth/microsoft_teams/callback` receives code, signals waiting thread |
| `CLI::Auth` | `cli/auth.rb` | `legion auth teams` command triggers BrowserAuth with ephemeral server |

## Auth Flow

```
User triggers auth:
  CLI: `legion auth teams`
  Settings: microsoft_teams.auth.delegated.enabled = true
  Bot command: `auth` or `login`

         ┌──────────────────────────┐
         │  Can we open a browser?  │
         └────────────┬─────────────┘
                yes   │   no (headless/SSH/TTY check)
          ┌───────────┴───────────┐
          ▼                       ▼
   Auth Code + PKCE         Device Code
          │                       │
   1. Generate PKCE pair    1. Request device_code
   2. Start callback server 2. Display URL + code
   3. Open browser          3. Auto-open browser to
   4. User signs in            devicelogin (if possible)
   5. Callback receives     4. Poll for token
      ?code=...&state=...
   6. Exchange code for
      tokens
          │                       │
          └───────────┬───────────┘
                      ▼
            Store tokens in Vault
            (access_token, refresh_token,
             expires_at, scopes)
                      │
                      ▼
            TokenCache holds in-memory copy
            Silent refresh before expiry
            Re-pop browser only if
            refresh_token is revoked/expired
```

### Headless Detection

- macOS: always assume GUI available
- Linux: check `ENV['DISPLAY']` or `ENV['WAYLAND_DISPLAY']`
- Windows: always assume GUI available
- Fallback: if `system("open", url)` (or platform equivalent) fails, switch to device code

### Browser Opening

Platform detection via `RbConfig::CONFIG['host_os']`:
- macOS: `system("open", url)`
- Linux: `system("xdg-open", url)`
- Windows: `system("start", url)`

(Pattern from `references/ruby_llm-mcp/lib/ruby_llm/mcp/auth/browser/opener.rb`)

### PKCE

- `code_verifier`: 43-128 character random string (`SecureRandom.urlsafe_base64(32)`)
- `code_challenge`: `Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)`
- `code_challenge_method`: `S256`

### State Parameter

- `SecureRandom.hex(32)` — verified on callback to prevent CSRF

### Callback Server (Ephemeral)

- `TCPServer.new('127.0.0.1', 0)` — OS assigns random available port
- Reads HTTP request, parses query string for `code` and `state`
- Returns a simple HTML "You can close this window" response
- Shuts down immediately after receiving the callback
- Timeout: 120 seconds (configurable)

### Callback Server (Sinatra/Daemon)

- `GET /api/oauth/microsoft_teams/callback`
- Receives `code` and `state`, signals a waiting `ConditionVariable`
- Returns HTML redirect or "Authentication complete" page

## Token Lifecycle

### Initial Auth (User-Triggered)

1. User triggers auth
2. BrowserAuth generates PKCE pair
3. Checks browser availability → Auth Code or Device Code
4. Obtains access_token + refresh_token
5. Writes to Vault at `vault_path`
6. TokenCache loads into memory

### Silent Refresh (Automatic)

1. TokenCache checks `expires_at - refresh_buffer` on every `cached_delegated_token` call
2. If within buffer: `POST oauth2/v2.0/token` with `grant_type=refresh_token`
3. Microsoft returns new access_token + rotated refresh_token
4. Write both back to Vault, update in-memory cache
5. No user interaction

### Re-Auth (Refresh Token Expired/Revoked)

1. Refresh returns `invalid_grant`
2. TokenCache clears delegated slot
3. Daemon running: trigger BrowserAuth via Sinatra callback route
4. CLI: prompt user to run `legion auth teams`
5. `Legion::Events.emit('microsoft_teams.auth.expired')` for extensions to react

### Daemon Startup

1. If `delegated.enabled: true`, read token from Vault
2. Valid (not expired) → load into TokenCache
3. Expired but refresh_token present → attempt silent refresh
4. No token or refresh fails → emit event, log message
5. Never auto-pop browser on startup without prior explicit auth

## Settings

```yaml
microsoft_teams:
  auth:
    tenant_id: "..."
    client_id: "..."
    client_secret: "..."              # client_credentials flow (existing)
    delegated:
      enabled: false                  # opt-in gate
      scopes: "OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access"
      refresh_buffer: 300             # seconds before expiry to refresh
      vault_path: "secret/legionio/microsoft_teams/delegated_token"
      callback_timeout: 120           # seconds to wait for browser callback
```

## Vault Storage

Path: `secret/legionio/microsoft_teams/delegated_token`

```json
{
  "access_token": "eyJ...",
  "refresh_token": "0.AR...",
  "expires_at": "2026-03-16T22:30:00Z",
  "scopes": "OnlineMeetings.Read OnlineMeetingTranscript.Read.All offline_access"
}
```

## Entra App Registration Requirements

The existing LegionIO Entra app needs:
- `fallback_public_client_enabled = true` (already set)
- `public_client.redirect_uris` must include `http://localhost` (wildcard port)
- Or register specific redirect URIs: `http://localhost:4567/api/oauth/microsoft_teams/callback` for daemon, and `http://localhost` for ephemeral
- Delegated permissions for desired scopes (requires admin consent in managed tenants)

## Scope

Teams-specific only. Build in lex-microsoft_teams, extract to a shared gem later if other extensions need it.

## Dependencies

No new gem dependencies. Uses:
- `SecureRandom`, `Digest::SHA256`, `Base64` (stdlib)
- `socket` (stdlib, for TCPServer)
- `legion-crypt` (existing, for Vault access)
- `faraday` (existing)
