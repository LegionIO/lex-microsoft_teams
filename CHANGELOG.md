# Changelog

## [Unreleased]

## [0.6.32] - 2026-03-31

### Fixed
- `IncrementalSync` actor: renamed `delay` to `time` so `Concurrent::TimerTask` actually uses the configured interval — was firing every 1s instead of every 120s
- `DirectChatPoller` default interval increased from 5s to 15s to reduce Graph API pressure
- `Meeting` absorber: renamed `handle` to `absorb` to match `Absorbers::Base` contract — `handle` was never called by the dispatch framework

### Added
- `Meeting` absorber: URL pattern for meeting chat links (`teams.microsoft.com/l/chat/19:meeting_**`) with chat thread resolution — extracts thread ID, fetches `onlineMeetingInfo.joinWebUrl` from the chat, then resolves the full meeting object

## [0.6.31] - 2026-03-31

### Fixed
- `CLI::Auth#login` now correctly extracts token from `result[:result]` (BrowserAuth return format), fixing CLI login never persisting to Vault or storing delegated token
- `CLI::Auth#store_token` now passes individual keyword args to `store_delegated_token` instead of the raw result hash

## [0.6.30] - 2026-03-31

### Fixed
- `TokenCache#vault_available?` now checks `:connected` instead of `:enabled`, preventing Vault calls before authentication is complete

## [0.6.29] - 2026-03-30

### Fixed
- `HighWaterMark#set_hwm` and `#set_extended_hwm`: pass `ttl:` as keyword arg to `cache_set` instead of positional arg, fixing `ArgumentError` in `ApiIngest`

## [0.6.28] - 2026-03-30

### Fixed
- `teams_auth_settings` in AuthValidator, TokenRefresher, and TokenCache now falls back to parent `[:microsoft_teams][:tenant_id]`/`[:client_id]` when not found under `[:auth]`, fixing browser auth never triggering when config uses top-level keys
- `TokenCache#teams_auth_settings` now includes ENV fallback for `AZURE_TENANT_ID`/`AZURE_CLIENT_ID` (previously missing, inconsistent with actor implementations) and parent-level `client_secret` fallback
- Silent rescue blocks in TraceRetriever (`format_single_trace`, `trace_age_label`), SubscriptionRegistry (`parse_stored`), and ProfileIngest runner (`ingest_self` presence fetch) now log errors instead of swallowing them

### Changed
- AuthValidator actor delay increased from 2s to 90s to allow Vault, transport, cache, and delegated auth to fully initialize before validation runs
- ProfileIngest actor delay increased from 5s to 95s to fire after AuthValidator completes (Once actor — no retry if token missing)
- ApiIngest actor delay increased from 10s to 95s to fire after AuthValidator completes delegated auth
- CLAUDE.md updated: added 5 undocumented actors (AbsorbMeeting, ApiIngest, ChannelPoller, MeetingIngest, PresencePoller), 3 runners (AiInsights, ApiIngest, Ownership), 1 helper (GraphClient), corrected spec counts

## [0.6.27] - 2026-03-29

### Changed
- Update to rubocop-legion 0.1.7 — resolve all 63 offenses
- Replace `defined?(Legion::Transport)` with `Legion.const_defined?(:Transport, false)` across 4 files
- Fix `llm_ask` call in `ProfileIngest` to use `message:` keyword (was `prompt:` + `caller:`)
- Add rescue variable captures (`=> _e`) for 5 rescue-logging offenses
- Add inline rubocop disables for 4 structural false positives
- Disable 3 cops in `.rubocop.yml` that produce systematic false positives
- Auto-correct Layout/ArgumentAlignment and Performance cops via rubocop -A

## [0.6.26] - 2026-03-29

### Fixed
- `Helpers::TokenCache` — replaced direct `Legion::Crypt.get(path)` call with `vault_get` from `Legion::Crypt::Helper` (included via `include Legion::Crypt::Helper`); `vault_path` accepts an optional `_suffix` argument so the helper's delegation pattern is compatible

## [0.6.25] - 2026-03-28

### Fixed
- `Hooks::Auth` — migrated from v2.0 `Routes::Hooks` pattern to v3.0 `LexDispatch` pattern: replaced instance `route`/`runner_class` overrides with a class-level `self.runner_class`; hook now registers as `POST /api/extensions/microsoft_teams/hooks/auth/handle` (was `/api/hooks/lex/microsoft_teams/auth/callback`)
- `Runners::Auth` — added `handle` alias for `auth_callback` so LexDispatch's default `:handle` routing resolves correctly
- `Helpers::BrowserAuth` — updated all three references to the hook redirect URI and probe path from the stale v2.0 path to `/api/extensions/microsoft_teams/hooks/auth/handle`

## [0.6.24] - 2026-03-28

### Added
- `Actors::AbsorbMeeting` — Subscription actor that listens on `lex.microsoft_teams.absorbers.meeting.absorb` and delegates to `Absorbers::Meeting#absorb`
- `Helpers::GraphClient` — mixin module wrapping `Helpers::Client#graph_connection` with `graph_get`, `graph_post`, `graph_paginate`, and an inline `GraphError` class for responses other than 200, 201, 204, or 404; 401/403 raise with descriptive messages including the Graph error body when available

### Fixed
- `Absorbers::Meeting#graph_token` — rescue now captures the exception as `=> e` and logs a warning, satisfying the rescue-logging lint rule

## [0.6.23] - 2026-03-27

### Changed
- `Absorbers::Meeting` — all Graph API runner calls now pass `token: graph_token` so requests carry an `Authorization` header in production. `graph_token` resolves from `Helpers::TokenCache.instance.cached_graph_token` when available, falling back to `nil` (unauthenticated) with a rescued `StandardError` to prevent test-environment boot failures
- `CLAUDE.md` — version field updated to 0.6.23

## [0.6.22] - 2026-03-27

### Changed
- `Absorbers::Meeting#handle` now fails fast with `{ success: false, error: 'meeting has no id' }` when the resolved meeting item has no `id` field, preventing subsequent runner calls from building invalid URLs
- `spec/legion/extensions/microsoft_teams/absorbers/meeting_spec.rb` — added spec covering the blank `meeting_id` guard path

## [0.6.21] - 2026-03-27

### Added
- `Absorbers::Meeting` — reference implementation of the absorber framework for Teams meetings. Resolves a Teams join URL to a meeting via Graph API, then ingests transcripts (VTT), AI insights, and participant lists into Apollo knowledge store. Two URL patterns registered: `teams.microsoft.com/l/meetup-join/*` and `*.teams.microsoft.com/meet/*`. Guard on `Legion::Extensions::Absorbers` ensures the absorber only loads when the framework base class is available.
- `spec/spec_helper.rb` — inline stubs for `Legion::Extensions::Absorbers::Base` and `Matchers::Url` so absorber specs run without the full `legionio` gem in the test environment

### Changed
- `lib/legion/extensions/microsoft_teams/absorbers/meeting.rb` — runner calls now go through `meetings_runner`, `transcripts_runner`, and `ai_insights_runner` instance accessors (`Object.new.extend(Runners::*)`) instead of calling runner modules directly as class methods, which would raise `NoMethodError` at runtime
- `spec/legion/extensions/microsoft_teams/absorbers/meeting_spec.rb` — specs stub runner instances via `absorber.meetings_runner` / `absorber.transcripts_runner` / `absorber.ai_insights_runner` rather than the module constants; `.patterns` spec no longer relies on `patterns.first` ordering; now asserts both expected pattern values are present in the set

## [0.6.19] - 2026-03-26

### Changed
- `TokenCache#vault_path` default now uses `users/` prefix: `users/{USER}/microsoft_teams/delegated_token` (where `{USER}` is `ENV.fetch('USER', 'default')`), aligning with Vault KV v2 policy structure that scopes secrets under per-user subpaths

## [0.6.18] - 2026-03-26

### Changed
- `TokenCache` Vault path is now per-user (`{USER}/microsoft_teams/delegated_token`) instead of hardcoded `legionio/microsoft_teams/delegated_token`

## [0.6.17] - 2026-03-24

### Added
- `Helpers::TraceRetriever` module: retrieves memory traces from the shared store at query time and formats them as LLM context (sender, teams, and chat-scoped domains; 2000-token budget; strength-ranked deduplication)
- `Bot#retrieve_trace_context` private method wires TraceRetriever into the handle_message flow
- `Bot#handle_message` now retrieves trace context before generating a response and passes it through to `generate_response` and `llm_respond`
- `SessionManager#get_or_create` seeds new sessions with profile traces for the owner via `trace_seed_for`
- `PromptResolver#resolve_prompt` accepts optional `trace_context:` keyword and appends it after preference instructions
- Comprehensive specs for TraceRetriever (token budget, rank/dedup, age labels, graceful degradation)
- Bot specs updated to verify trace context retrieval and pass-through, and nil/graceful-degradation paths

### Changed
- Add `caller:` identity to `llm_chat` calls in bot and profile_ingest runners for pipeline attribution

## [0.6.15] - 2026-03-23

### Added
- Apollo knowledge graph integration: ingest conversation observations and extract entities from Teams messages
- `publish_to_apollo` feeds per-person message summaries into Apollo's knowledge store as observations
- `extract_and_ingest_entities` uses Apollo EntityExtractor to identify people, services, repos, and concepts
- Soft guards: Apollo integration is a no-op when lex-apollo or legion-data are not loaded

## [0.6.14] - 2026-03-23

### Added
- Graph API ingest runner and actor for fetching top contacts and their 1:1 chat messages
- People-based chat matching with email, userId, and displayName fallbacks
- High-water mark support for incremental message fetching
- Paginated chat fetching with MAX_CHAT_PAGES cap

### Changed
- Replace all silent rescue blocks with log.debug/warn/error entries
- Use `log.` helper consistently instead of `Legion::Logging.`
- Fix `IncrementalSync#resolve_token` to use `TokenCache.instance` instead of `.new`
- Clean up debug logging (remove log.unknown/log.fatal, use log.debug)

## [0.6.13] - 2026-03-22

### Changed
- Add legion-data, legion-json, and legion-transport as runtime dependencies
- Include `Legion::Data::Helper`, `Legion::JSON::Helper`, and `Legion::Transport::Helper` in spec_helper Lex stub

## [0.6.12] - 2026-03-22

### Changed
- Add legion-cache and legion-crypt as runtime dependencies
- Include `Legion::Cache::Helper` and `Legion::Crypt::Helper` in spec_helper Lex stub

## [0.6.11] - 2026-03-22

### Changed
- Add legion-logging and legion-settings as runtime dependencies
- Include `Legion::Settings::Helper` in spec_helper Lex stub for real settings access in tests

## [0.6.10] - 2026-03-22

### Changed
- Replace spec_helper Helpers::Lex stub with real `Legion::Logging::Helper` from legion-logging gem
- Add legion-logging >= 1.3.2 as test dependency

## [0.6.9] - 2026-03-22

### Changed
- Replace direct `Legion::Logging` calls with injected `log` helper from `Helpers::Lex` across all actors, runners, helpers, and CLI
- Remove private `log_debug`, `log_info`, `log_warn`, `log_error` wrapper methods (net -161 lines)
- Add `Helpers::Lex` stub in spec_helper for test environment compatibility

## [0.6.8] - 2026-03-22

### Fixed
- TokenCache deadlock: `cached_delegated_token` held `@mutex` while calling `refresh_delegated` -> `save_to_local` which re-acquired `@mutex`. Moved refresh outside synchronize block.

### Added
- INFO logging in ProfileIngest and CacheBulkIngest `manual` methods for boot-time visibility

## [0.6.7] - 2026-03-22

### Fixed
- ProfileIngest actor uses `TokenCache.instance` singleton instead of `TokenCache.new` (empty cache returned nil token, preventing boot-time profile ingest)

## [0.6.6] - 2026-03-22

### Added
- `Bot.dispatch_message` routes AMQP messages by mode (direct -> handle_message, observe -> observe_message)
- MeetingIngest stores transcripts as episodic traces and AI insights as semantic traces in lex-agentic-memory
- ChannelPoller stores new channel messages as episodic traces in lex-agentic-memory
- INFO-level poll logging in MeetingIngest and ChannelPoller for visibility

### Changed
- MessageProcessor actor now calls `dispatch_message` instead of `handle_message` directly

## [0.6.5] - 2026-03-22

### Added
- `Actors::ChannelPoller` (Every, 60s): polls joined team channels for new messages with HWM dedup
- `Actors::MeetingIngest` (Every, 5min): polls online meetings, fetches transcripts (VTT) and AI insights
- `Actors::PresencePoller` (Every, 60s): polls Graph API presence, logs changes at INFO
- `Runners::AiInsights` for Graph API meeting AI insights, recordings, and call records
- All 28 Entra delegated permission scopes in `BrowserAuth::DEFAULT_SCOPES`
- Comprehensive tagged logging throughout auth, token, and poller lifecycles
- `TokenCache.instance` singleton pattern for shared token state across all actors
- `force_local_server` option in `BrowserAuth` for CLI OAuth flow
- `hook_route_registered?` HTTP probe for daemon OAuth callback detection
- Environment variable fallback (`AZURE_TENANT_ID`, `AZURE_CLIENT_ID`) in CLI and actors

### Fixed
- Fix memory namespace: `Legion::Extensions::Memory::*` -> `Legion::Extensions::Agentic::Memory::Trace::*` across 6 files
- Fix `SubscriptionRegistry` using nonexistent `recall_trace` method, now uses `retrieve_by_domain`
- Fix Vault write attempts when `crypt.vault.enabled` is false (added `vault_available?` guard)
- Fix token not shared across actors (each created own `TokenCache.new` instead of singleton)
- Fix app token warning spam with warn-once pattern and delegated token fallback

### Changed
- Updated `AuthValidator` spec to match rewritten `manual` method logic

## [0.6.4] - 2026-03-22

### Added
- `auto_authenticate` setting (`settings[:microsoft_teams][:auth][:delegated][:auto_authenticate]`, default `false`) — when true, triggers browser OAuth popup on boot even for first-time users with no prior token

## [0.6.3] - 2026-03-22

### Fixed
- Add `extend self` to `Runners::ProfileIngest` so methods are callable at module level by framework actor dispatch
- Add token guard to `IncrementalSync` and `ProfileIngest` actors to skip execution when no valid delegated token exists

## [0.6.1] - 2026-03-21

### Fixed
- Guard nil settings in IncrementalSync actor `args` and `delay` methods — `Legion::Settings[:microsoft_teams]` can return nil without raising

## [0.6.0] - 2026-03-20

### Added
- `Runners::People` with `get_profile` and `list_people` (Graph API `/me` and `/me/people`)
- `Runners::ProfileIngest` four-phase pipeline (self, people, conversations, teams/meetings)
- `Helpers::PermissionGuard` circuit breaker for 403 errors with exponential backoff
- `Helpers::TransformDefinitions` for lex-transformer conversation extraction and person summary
- `Actors::ProfileIngest` (Once): four-phase data pipeline at boot after auth
- `Actors::IncrementalSync` (Every, 15min): periodic re-sync with HWM dedup
- `CLI::Auth` module for `legion lex teams auth login/status`
- Extended high-water mark with dual timestamps and procedural trace persistence
- `People.Read` delegated permission scope

### Changed
- `Helpers::HighWaterMark` extended with `get/set/update_extended_hwm`, trace persistence, restore

## [0.5.6] - 2026-03-19

### Added
- BrowserAuth API hook detection: uses hook URL when Legion::API is running instead of ephemeral CallbackServer
- `api_hook_available?` and `hook_redirect_uri` methods on BrowserAuth
- `authenticate_via_hook` path using `Legion::Events` for callback notification
- `authenticate_via_server` extracted from original `authenticate_browser` as fallback path

### Changed
- `authenticate_browser` now delegates to hook path (API running) or server path (standalone)

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
