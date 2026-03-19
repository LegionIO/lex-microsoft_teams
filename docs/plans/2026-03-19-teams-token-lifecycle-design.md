# Teams Token Lifecycle Design

## Summary

Add automatic delegated token management to lex-microsoft_teams: validate on boot, refresh on a timer, and re-authenticate via browser when a previously authenticated user's token expires.

## Problem

Currently, delegated tokens require manual `legion auth teams` invocation. If a token expires between restarts (or the refresh token dies), nothing recovers it. Pollers silently fail because `cached_delegated_token` returns nil.

## Approach

Two new actors + TokenCache enhancements. Follows the existing actor conventions (CacheBulkIngest is Once, DirectChatPoller is Every).

## Components

### TokenCache Enhancements

Two new public methods on `Helpers::TokenCache`:

- `authenticated?` — returns true when `@delegated_cache` is non-nil (live token in memory)
- `previously_authenticated?` — returns true when the local token file exists on disk (user opted in before)

The distinction: `previously_authenticated?` means "user said yes before" (file exists). `authenticated?` means "we have a live token right now." This controls whether auto re-auth fires (only for returning users) vs staying silent (never-authenticated users).

### AuthValidator Actor (Once)

`Actor::AuthValidator < Legion::Extensions::Actors::Once`

Runs once on boot with a 2-second delay. Sequence:

1. Create TokenCache instance
2. Call `token_cache.load_from_vault` (tries Vault, falls back to local file)
3. If loaded: try `cached_delegated_token` (triggers internal refresh if expired)
   - Refresh succeeds: log info "Teams delegated auth restored"
   - Refresh fails + `previously_authenticated?`: log warning, fire BrowserAuth
   - Refresh fails + not previously authenticated: silent (user never opted in)
4. If nothing loaded: check `previously_authenticated?`
   - True: log warning, fire BrowserAuth (file corrupt or unloadable)
   - False: log debug "No Teams delegated auth configured" — silent

Does NOT touch the app token (client_credentials). That is handled lazily by `cached_graph_token` in the pollers.

### TokenRefresher Actor (Every)

`Actor::TokenRefresher < Legion::Extensions::Actors::Every`

Runs every 15 minutes (configurable). Each tick:

1. Guard: `return unless token_cache.authenticated?`
2. Call `cached_delegated_token` (internally refreshes if within 60s of expiry)
3. If token returned: `save_to_vault` (persists to local file + optional Vault). Done.
4. If nil (refresh failed):
   - `previously_authenticated?` true: log warning, fire BrowserAuth
   - Otherwise: do nothing (delegated_cache already nil)

`run_now?` = false (AuthValidator handles the initial check).

### BrowserAuth Trigger

Both actors use the same private `attempt_browser_reauth` method:

1. Read tenant_id, client_id, scopes from settings
2. Log warning: "Delegated token expired, opening browser for re-authentication..."
3. Create `BrowserAuth.new(...)` and call `authenticate`
4. On success: `store_delegated_token` + `save_to_vault`
5. On failure: log error, return false

BrowserAuth already detects headless environments (no DISPLAY/WAYLAND) and falls back to device code flow. No special handling needed.

Both actors define this method privately. No shared module — it is ~20 lines, used in two places, and a premature abstraction would add complexity for no gain.

### Shared TokenCache Instance

AuthValidator and TokenRefresher each create their own TokenCache instance. This is fine because the local file is the source of truth. AuthValidator loads on boot, TokenRefresher refreshes and saves back to the file on each tick.

## Configuration

Settings path: `Legion::Settings[:microsoft_teams][:auth][:delegated]`

New key:

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `refresh_interval` | Integer (seconds) | 900 | TokenRefresher polling interval |

Existing keys unchanged: `refresh_buffer`, `scopes`, `vault_path`, `local_token_path`.

## Testing

### TokenCache Specs
- `authenticated?` returns false with no cache, true after store
- `previously_authenticated?` returns false with no file, true after save_to_local

### AuthValidator Specs
- Loads token and refreshes successfully (log info)
- Loads token, refresh fails, previously authed -> triggers browser reauth
- Loads token, refresh fails, never authed -> silent
- No token file exists -> silent

### TokenRefresher Specs
- Skips when not authenticated
- Refreshes successfully and saves
- Refresh fails, previously authed -> triggers browser reauth

### Actor Patterns
- Stub base classes with `$LOADED_FEATURES` injection + `described_class.allocate`
- Stub TokenCache and BrowserAuth (no real network calls)

## Files Changed

| File | Change |
|------|--------|
| `helpers/token_cache.rb` | Add `authenticated?`, `previously_authenticated?` |
| `actors/auth_validator.rb` | New file |
| `actors/token_refresher.rb` | New file |
| `spec/.../helpers/token_cache_spec.rb` | Add 4 specs |
| `spec/.../actors/auth_validator_spec.rb` | New file |
| `spec/.../actors/token_refresher_spec.rb` | New file |
| `microsoft_teams.rb` | Require new actor files |
