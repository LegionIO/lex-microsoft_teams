# Changelog

## [0.5.5] - 2026-03-19

### Added
- `Hooks::Auth` hook class with `mount '/callback'` for OAuth redirect via expanded hooks system
- `Runners::Auth#auth_callback` method handling OAuth callback with HTML response and event emission
- OAuth callback now routes through `Ingress.run` for RBAC and audit support

### Changed
- OAuth callback URL moves from hardcoded `/api/oauth/microsoft_teams/callback` to `/api/hooks/lex/microsoft_teams/auth/callback`

## [0.5.4] - 2026-03-19

### Added
- `TokenCache#authenticated?` predicate for runtime delegated token state
- `TokenCache#previously_authenticated?` predicate for persistent auth history
- `AuthValidator` actor (Once): validates and restores delegated tokens on boot
- `TokenRefresher` actor (Every, 15min configurable): keeps delegated tokens fresh
- Automatic browser re-auth when previously authenticated user's token expires
- `refresh_interval` config key at `settings[:microsoft_teams][:auth][:delegated]`

## [0.5.3] - 2026-03-19

### Added
- `user_path` helper in `Helpers::Client` for Graph API `/me/` vs `/users/{id}/` flexibility
- `user_id: 'me'` default on all meeting, transcript, presence, chat, and team runner methods
- `user_id:` parameter on `Client` constructor for application-permission workflows

### Fixed
- RecordParser 3-byte varint decoding: added missing `& 0x7F` mask on third byte
- MessageProcessor actor namespace: `Actors` to `Actor` for consistency with all other actors
- `Client#authenticate!` nil guard preventing `NoMethodError` on failed token acquisition
- CallbackServer error handling: separate `IOError` (shutdown) from unexpected errors
- SubscriptionRegistry now calls `load` on initialization to restore persisted subscriptions
- Device code polling: collapsed duplicate case branches for cleaner error handling

### Removed
- Dead `transport.rb` file (never required by any code path)
- Dead `.tap` block in CacheSync `args` method
- Dead `conversation_overrides` TODO stub in PromptResolver (simplified to nil return)

### Changed
- `strip_html` in CacheIngest moved from public to private
- Token cache spec cleanup: atomic file operations, `Process.pid` over `$$`

## [0.5.2] - 2026-03-18

### Fixed
- CallbackServer Ruby 4.0 compatibility: replaced `CGI.parse` with `URI.decode_www_form` (avoids extracted cgi gem dependency)
- CallbackServer header drain loop: fixed infinite loop when client disconnects before sending empty line
- Broadened rescue in listen thread to `StandardError` to prevent silent thread death

## [0.5.1] - 2026-03-17

### Added
- `Transport` module extending `Legion::Extensions::Transport` to provide the `build` method expected by LegionIO's `build_transport`

## [0.5.0] - 2026-03-16

### Added
- Delegated OAuth browser flow with Authorization Code + PKCE
- Automatic Device Code fallback for headless environments
- `Helpers::BrowserAuth` orchestrator (PKCE generation, headless detection, browser opening)
- `Helpers::CallbackServer` ephemeral TCP server for OAuth redirect
- `Runners::Auth#authorize_url`, `#exchange_code`, `#refresh_delegated_token` methods
- `Helpers::TokenCache` delegated token slot with Vault persistence and silent refresh
- `legion auth teams` CLI command (in LegionIO) for interactive authentication
- `GET /api/oauth/microsoft_teams/callback` Sinatra route (in LegionIO) for daemon re-auth

### Fixed
- `poll_device_code` now persists `slow_down` interval increase per RFC 8628
- `poll_device_code` returns error hash on timeout instead of raising RuntimeError

## [0.4.1] - 2026-03-15

### Added
- Preference commands: `prefer <value>`, `preferences`, `reset preferences`
- PromptResolver queries PreferenceProfile for per-user system prompt customization
- SessionManager passes owner_id through to PromptResolver
- `SessionManager#refresh_prompt` rebuilds system prompt without clearing history

## [0.4.0] - 2026-03-15

### Added
- Meetings runner: list, get, create, update, delete online meetings, lookup by join URL, attendance reports
- Transcripts runner: list, get metadata, get content (VTT/DOCX format support)
- New Graph API permissions: `OnlineMeeting.Read.All`, `OnlineMeetingTranscript.Read.All`

## [0.3.0] - 2026-03-15

### Added
- Token cache helper with 60-second pre-expiry automatic refresh
- Subscription registry with in-memory store and lex-memory persistence
- Command handler for bot DMs: watch, unwatch, list, pause, resume
- Token cache wired into DirectChatPoller and ObservedChatPoller
- Subscription registry wired into ObservedChatPoller

## [0.2.0] - 2026-03-15

### Added
- AI bot with direct chat mode (LLM-powered 1:1 responses via polling)
- Conversation observer mode (task/context extraction from watched chats, default disabled)
- AMQP-based message routing (teams.messages exchange and queue)
- Session manager with lex-memory persistence for multi-turn conversations
- Layered prompt resolver (settings -> mode -> per-conversation overrides)
- High-water mark tracking for message deduplication
- DirectChatPoller actor (5s interval, Graph API polling)
- ObservedChatPoller actor (30s interval, compliance-gated)
- MessageProcessor subscription actor (AMQP consumer, routes by mode)

## [0.1.0] - 2026-03-13

### Added
- Initial release
