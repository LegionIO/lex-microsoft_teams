# Changelog

## [0.6.52] - 2026-05-29
### Fixed
- **Actors now defer their next scheduled run on a Graph throttle** instead of re-firing on their fixed timer interval — resolves the 0.6.51 "Known follow-up". New `Helpers::ThrottleAware` mixin records a "suppress until" instant of `now + retry_after` when a Graph call raises `Errors::Throttled`; subsequent ticks short-circuit until that window elapses. Wired into `PresencePoller`, `MeetingIngest`, and `ApiIngest`. Falls back to a bounded 60s deferral when the server gave no usable `Retry-After`, and clamps any single deferral to 600s. Previously a poller on a 30–300s interval would walk straight back into the still-open shared circuit every interval, emitting a `[throttle_circuit] hard circuit` ERROR (and a duplicate `Errors::Throttled` WARN/ERROR) each tick while ingesting nothing.
- **`ProfileIngest#full_ingest` and `ApiIngest#ingest_api` now propagate `Errors::Throttled`** rather than folding it into a per-stage error hash. `full_ingest` catches it once and aborts the remaining fan-out stages — once the shared circuit is open every later stage would only raise `Throttled(attempts: 0)` instantly, so continuing produced a burst of identical errors. The actor that drives `ingest_api` uses the propagated throttle to open its deferral window. Non-throttle errors keep their existing error-result behavior.

## [0.6.51] - 2026-05-27
### Added
- `Faraday::RetryAfter` middleware honoring `Retry-After` per RFC 9110 §10.2.3 (originally RFC 7231 §7.1.3) in both delta-seconds and HTTP-date forms. Retries HTTP 429 by default; 503/504 opt-in. Bounded by `max_retries` and cumulative `max_wait`; ±jitter on advertised wait to avoid thundering-herd. Configurable via `microsoft_teams.client.retry.{max_retries,max_wait,jitter,fallback_wait,retry_statuses}`; `fetch` semantics preserve explicit falsey values.
- `Errors::Throttled` exception with `status`, `retry_after` (nullable; `nil` distinguishes "no server guidance" from "retry immediately"), `retry_after_known?` predicate, `request`, and `attempts`.
- `Faraday::RetryAfter.parse_header` shared class method (single source of truth for Retry-After parsing).
- `default_settings` for all actors with explicit `enabled`, `interval`, and tuning knobs. Actors no longer need nil guards — values are guaranteed by the extension settings merge on boot. Defaults: `api_ingest` 3600s, `incremental_sync` 900s, `presence_poller` disabled, `channel_poller` disabled, `direct_chat_poller` disabled, `observed_chat_poller` disabled, `meeting_ingest` 900s, `profile_ingest` enabled (once on boot).
- `Helpers::GraphCache` module — `cached_graph_get` wraps Graph API calls with `Legion::Cache` TTL-based caching. Supports `shared: true` for resource-scoped endpoints (e.g., `/chats/{id}/members` — same data for all participants) vs user-scoped for `/me/*` endpoints. Cache keys incorporate the process identity UUID to prevent cross-user leakage.

### Fixed
- Stuck or chatty consumers no longer brown out other users on the same Entra app registration's Graph quota. The `RetryAfter` middleware now raises `Errors::Throttled` **centrally on exhaustion** — every consumer of `graph_connection` and `bot_connection` gets the typed event without per-callsite handling. Fixes #18.
- `Helpers::GraphClient#handle_graph_response` retains a defensive 429/503/504 branch that raises `Errors::Throttled` for callers that build a Faraday connection without the middleware (custom tests, ad-hoc tooling).
- Logger acquisition failures no longer silently drop retry telemetry — falls back to `Legion::Logging` unconditionally; loss of those signals was how the original outage went undiagnosed for days.
- **O(N×M) member scan eliminated** — `ProfileIngest#find_chat_for_person` and `ApiIngest#match_chat_to_person` previously called `GET /chats/{id}/members` for every chat × every person (up to 500+ calls per tick). Replaced with `build_chat_member_index` that fetches members once per chat and builds an in-memory lookup hash. Reduces ~514 calls/tick to ~50 for `IncrementalSync`; ~7,500 calls/tick to ~65 for `ApiIngest`.
- `IncrementalSync` interval raised from 120s to 900s (was the single largest source of sustained Graph pressure).
- `ApiIngest` interval raised from 1800s to 3600s.
- Actors that were accidentally re-enabled by `952607c` (rubocop removed `return false` guards) are now properly gated by `settings[:actor_name][:enabled]` — `presence_poller`, `channel_poller`, `direct_chat_poller`, and `observed_chat_poller` all default to `false`.

### Known follow-up
- Actors (`*_poller.rb`, `meeting_ingest`, `profile_ingest`) still catch `Errors::Throttled` via the generic `rescue StandardError` block but do not yet *defer their next scheduled run* using the carried `retry_after`. To be addressed in a follow-up issue. *(Resolved in [Unreleased] — see `Helpers::ThrottleAware`.)*

## [0.6.50] - 2026-05-27
### Added
- Full OData query parameter support across all Graph API runner methods per Microsoft Graph REST v1.0 docs
- `max_pages` pagination parameter on all list endpoints — follows `@odata.nextLink` automatically to fetch multiple pages in a single call
- `$top` exposed in MCP inputs for: list_chat_messages, list_chats, list_channel_messages, list_channel_message_replies, list_message_replies, list_team_members, list_meetings, list_drive_items, list_team_drive_items, list_call_sessions, list_session_segments, list_meeting_artifacts, list_transcripts
- `$orderby` support for list_chat_messages (lastModifiedDateTime desc, createdDateTime desc) and list_chats (lastMessagePreview/createdDateTime desc)
- `$filter` support for list_chat_messages, list_chats, list_channels, list_joined_teams, list_team_members, list_meetings, list_drive_items, list_people
- `$expand` support for list_chats (members, lastMessagePreview), list_channel_messages (replies), list_installed_apps_for_user, list_installed_apps_in_chat, list_call_sessions (segments)
- `$select` support for list_channels, list_joined_teams, list_drive_items, list_team_drive_items, list_call_sessions, list_people
- `$search` support for list_people
- `format` (vtt/docx) exposed in MCP inputs for get_transcript_content

### Fixed
- Per-page size capped at Graph API maximum (50 for messages/chats, 200 for drive items) regardless of `top` value passed

## [0.6.48] - 2026-05-18
### Added
- Definition DSL declarations across all runners for proper tool discovery and MCP exposure
- Fix transformer API: map definition[:prompt] to transform(transformation:) for lex-transformer 0.3.8

### Fixed
- Bot response and observation extraction now pass explicit system and user messages to native `Legion::LLM.chat` dispatch instead of routing through the legacy nil-input `llm_chat` helper path.
- Runner modules that declare `definition` now explicitly `extend Legion::Extensions::Definitions` before those DSL calls, fixing `NoMethodError: undefined method 'definition'` during Legion extension boot.

## [0.6.45] - 2026-04-23

### Added
- `Runners::Meetings#resolve_meeting` — accepts `chat_thread_id:` (e.g., `19:meeting_...@thread.v2`) or `join_url:` (e.g., `https://teams.microsoft.com/meet/CODE`). When given a chat thread ID, fetches the chat to extract the `joinWebUrl` from `onlineMeetingInfo`, then resolves the actual meeting object via `get_meeting_by_join_url`. Bridges the gap between meeting URLs and Graph API meeting endpoints which require the real meeting ID

### Fixed
- `Runners::AiInsights#list_call_records` — removed `$top` query parameter not supported by the `communications/callRecords` Graph API endpoint (`Query option 'Top' is not allowed`)

## [0.6.44] - 2026-04-23

### Fixed
- `TokenCache#teams_auth_settings` — `settings` (from `Settings::Helper`) looks up `Legion::Settings[:extensions][:microsoft_teams]` which is empty because Teams config lives at `Legion::Settings[:microsoft_teams]`. Added fallback to `Legion::Settings[:microsoft_teams]` when `settings` returns empty, restoring tenant_id/client_id resolution for token refresh. This was the root cause of "Missing tenant_id or client_id for delegated refresh" immediately after successful OAuth login

## [0.6.43] - 2026-04-23

### Fixed
- `Helpers::Client#graph_connection` — added `TokenCache.instance.cached_delegated_token` fallback when no `token:` kwarg is passed and settings has no static token. Fixes "Access token is empty" errors when runners are invoked via LLM tool dispatch without an explicit token argument
- `Helpers::Client#bot_connection` — same fix using `TokenCache.instance.cached_app_token`

## [0.6.42] - 2026-04-23

### Fixed
- `Helpers::TokenCache#vault_path` — replaced `ENV.fetch('USER', 'default')` with `Legion::Identity::Process.canonical_name` (the resolved Kerberos/LDAP identity), matching the pattern used in `legion-llm` PR #80. Falls back to `ENV['USER'].split('@').first` (email domain stripped) if Identity is not yet resolved
- Also removed the `microsoft_teams` namespace segment from the returned suffix — `Crypt::Helper#vault_write` wraps the path in its own `vault_path(suffix)` which already prepends the lex namespace, so including it again caused double-prefixed Vault paths (`microsoft_teams/users/.../microsoft_teams/delegated_token`).
- Final Vault path is now: `microsoft_teams/users/{canonical_name}/delegated_token`
- Configurable via `settings[:auth][:delegated][:vault_path]` if a custom path is needed

## [0.6.41] - 2026-04-23

### Fixed
- `Helpers::Client#graph_connection` and `#bot_connection` — replaced `Legion::Settings[:microsoft_teams]` with `settings` (provided by `Legion::Settings::Helper` via `Helpers::Lex`), which correctly scopes to the lex key automatically and is the approved pattern inside a lex
- `Helpers::TokenCache#teams_auth_settings` — same fix; replaced `Legion::Settings[:microsoft_teams]` with `settings`, removed the now-redundant `defined?(Legion::Settings)` guard and `if ms` nil guards (settings always returns a Hash)
- The only remaining `Legion::Settings` references in `token_cache.rb` are for cross-lex lookups (`:crypt, :vault, :connected`) which are intentional and correct
- Token write paths (`save_to_local`, `save_to_vault`) confirmed clean — write to `local_token_path` (defaulting to `~/.legionio/tokens/`) and Vault respectively, not into settings

## [0.6.40] - 2026-04-23

### Fixed
- `Helpers::BrowserAuth` — removed private `log` method that was shadowing the `log` accessor provided by `Legion::Extensions::Helpers::Lex`. The `include Helpers::Lex` guard was already present but the manual fallback overrode it; all `log.debug/info/warn/error` calls now correctly route through the Lex helper (structured logging, context propagation, etc.)

## [0.6.39] - 2026-04-23

### Added
- `Absorbers::Chat` — absorbs a Teams chat thread into Apollo by URL (`teams.microsoft.com/l/chat/19:*@*`). Extracts the chat ID from the URL, fetches metadata, pulls messages (with inline replies, HTML stripped), and ingests participants. Content types: `teams_chat_thread`, `teams_chat_participants`
- `Absorbers::Channel` — absorbs a Teams channel or specific thread into Apollo by URL (`teams.microsoft.com/l/channel/*`, `teams.microsoft.com/l/message/*`). Extracts `team_id` from `groupId` query param and `channel_id` from path. When a `message_id` is present (deep-link to a specific thread) only that thread is ingested; otherwise the top 50 channel messages are ingested. Replies are fetched and inlined. Content types: `teams_channel_thread`, `teams_channel_members`
- `Actors::AbsorbChat` — Subscription actor delegating to `Absorbers::Chat#absorb`, mirrors the `AbsorbMeeting` actor pattern
- `Actors::AbsorbChannel` — Subscription actor delegating to `Absorbers::Channel#absorb`, mirrors the `AbsorbMeeting` actor pattern
- Both new absorbers and actors are conditionally required (gated on `Legion::Extensions::Absorbers::Base` presence) in `microsoft_teams.rb`

## [0.6.38] - 2026-04-23

### Fixed
- `Helpers::Client#graph_connection` now falls back to `Legion::Settings[:microsoft_teams]&.dig(:auth, :delegated, :token)` when no `token:` is explicitly passed — fixes unauthenticated Graph API calls when runners are invoked as standalone modules via Lex tool dispatch (not via an instantiated `Client` object where `@opts` carries the token)
- `Helpers::Client#bot_connection` applies the same fallback using `Legion::Settings[:microsoft_teams]&.dig(:auth, :bot, :token)`

## [0.7.0] - unreleased

### Added
- New `Runners::Loop` module with four functions for Microsoft Loop component support via `fluidEmbedCard`:
  - `create_loop_file` — Creates a new `.loop` file in a user's OneDrive via the Graph API; returns drive item metadata including `webUrl`
  - `loop_attachment` — Builds the `fluidEmbedCard` + placeholder attachment pair required to embed a Loop component in a Teams message
  - `post_loop_to_chat` — Posts a Loop component inline into a Teams chat thread
  - `post_loop_to_channel` — Posts a Loop component inline into a Teams channel thread
- Requires `Files.ReadWrite` and `Sites.ReadWrite.All` Graph API permissions for `create_loop_file`; `Chat.ReadWrite` and `ChannelMessage.Send` are already required by existing runners
- **Note:** Programmatic write access to Loop page *content* (Fluid Framework) is not yet available via Microsoft Graph; Loop files must be opened in Teams to initialize the collaborative session

## [0.6.36] - 2026-04-13

### Fixed
- `TokenCache#load_from_vault` now passes `vault_path` explicitly to `vault_get`, matching the `save_to_vault` pattern (#10)

## [0.6.35] - 2026-04-09

### Changed
- Split `cached_graph_token` into separate `cached_delegated_token` and `cached_app_token` helpers in `TokenCache` — delegated token used for user-context calls, app token for application-credential (client_credentials) calls
- Added `Broker` soft consumer actor to cache app tokens via client_credentials flow without blocking extension boot
- Updated all actors (ChannelPoller, DirectChatPoller, MeetingIngest, ObservedChatPoller, PresencePoller) to route token selection based on call context: delegated token for user-scoped Graph API paths, app token for app-scoped paths

## [0.6.34] - 2026-04-03

### Fixed
- ApiIngest restores HWM from traces on startup to prevent re-fetching all messages on every restart
- ApiIngest now fetches 1:1, group, and meeting chats (not just oneOnOne)
- CacheSync disabled — local cache has no chat type metadata to filter channel messages
- ChannelPoller trace storage gated behind `channels.store_traces` setting (default: false)

## [0.6.33] - 2026-04-03

### Changed
- Set `remote_invocable? false` — eliminates 19 auto-generated AMQP subscription actors on boot
- Add initial delays to Every actors: DirectChatPoller (60s), ObservedChatPoller (180s), ChannelPoller (300s), IncrementalSync (60s), ApiIngest (max of auth_delay+5 or 30s)
- Disable CacheBulkIngest until run-once-ever logic is implemented

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
