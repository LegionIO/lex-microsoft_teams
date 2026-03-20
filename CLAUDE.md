# lex-microsoft_teams: Microsoft Teams Integration for LegionIO

**Repository Level 3 Documentation**
- **Parent (Level 2)**: `/Users/miverso2/rubymine/legion/extensions/CLAUDE.md`
- **Parent (Level 1)**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Legion Extension that connects LegionIO to Microsoft Teams via Graph API and Bot Framework. Provides runners for chats, channels, messages, subscriptions (change notifications), adaptive cards, bot communication, and an AI-powered bot with conversation observation.

**GitHub**: https://github.com/LegionIO/lex-microsoft_teams
**License**: MIT
**Version**: 0.5.6

## Architecture

```
Legion::Extensions::MicrosoftTeams
├── Runners/
│   ├── Auth              # OAuth2 client credentials (Graph + Bot Framework) + auth_callback for hook
│   ├── Teams             # List/get teams, members
│   ├── Chats             # 1:1 and group chat CRUD
│   ├── Messages          # Chat message send/read/reply
│   ├── Channels          # Team channel CRUD
│   ├── ChannelMessages   # Channel message send/read/reply
│   ├── Subscriptions     # Graph change notification webhooks
│   ├── AdaptiveCards     # Adaptive Card payload builder
│   ├── Bot               # Bot Framework + AI bot (handle_message, handle_command, observe_message)
│   ├── Presence          # Graph API user presence
│   ├── Meetings          # Online meeting CRUD, join URL lookup, attendance reports
│   ├── Transcripts       # Meeting transcript list/get/content (VTT/DOCX)
│   ├── LocalCache        # Offline message extraction from local LevelDB cache
│   └── CacheIngest       # Ingest cached messages into lex-memory as episodic traces
├── Actors/
│   ├── CacheBulkIngest       # Once: full cache ingest at startup (imprint window support)
│   ├── CacheSync             # Every 5min: incremental ingest of new messages
│   ├── DirectChatPoller      # Every 5s: polls bot DM chats via Graph API
│   ├── ObservedChatPoller    # Every 30s: polls subscribed human conversations (compliance-gated)
│   ├── MessageProcessor      # Subscription: consumes AMQP queue, routes by mode
│   ├── AuthValidator         # Once: validates/restores delegated tokens on boot (2s delay)
│   └── TokenRefresher        # Every 15min (configurable): keeps delegated tokens fresh
├── Transport/
│   ├── Exchanges/Messages    # teams.messages topic exchange
│   ├── Queues/MessagesProcess # teams.messages.process durable queue
│   └── Messages/TeamsMessage  # Message schema with routing key
├── LocalCache/
│   ├── SSTableReader     # Pure Ruby LevelDB .ldb file reader (Snappy decompression)
│   ├── RecordParser      # Chromium IndexedDB value parser (field-value pairing)
│   └── Extractor         # Message extraction, filtering, dedup from local cache
├── Helpers/
│   ├── Client            # Three connection builders (Graph, Bot, OAuth)
│   ├── HighWaterMark     # Per-chat message dedup via legion-cache (with in-memory fallback)
│   ├── PromptResolver    # Layered system prompt resolution (settings -> mode -> per-conversation)
│   ├── SessionManager    # Multi-turn LLM session lifecycle with lex-memory persistence
│   ├── TokenCache        # In-memory OAuth token cache with pre-expiry refresh (app + delegated slots, authenticated?/previously_authenticated? predicates)
│   ├── SubscriptionRegistry # Conversation observation subscriptions (in-memory + lex-memory)
│   ├── BrowserAuth       # Delegated OAuth orchestrator (PKCE, headless detection, browser launch, API hook detection)
│   └── CallbackServer    # Ephemeral TCP server for OAuth redirect callback
├── Hooks/
│   └── Auth              # OAuth callback hook (mount '/callback') → /api/hooks/lex/microsoft_teams/auth/callback
└── Client                # Standalone client (includes all runners)
```

## Delegated Authentication (v0.5.0)

Opt-in browser-based OAuth for delegated Microsoft Graph permissions. Two flows:

- **Authorization Code + PKCE** (primary): Opens browser for Entra ID login. When the Legion API is running, uses the hook URL (`/api/hooks/lex/microsoft_teams/auth/callback`) with `Legion::Events` for callback notification; otherwise falls back to an ephemeral local port via `CallbackServer`
- **Device Code** (fallback): Auto-selected in headless/SSH environments (no `DISPLAY`/`WAYLAND_DISPLAY`)

Tokens stored in Vault (`legionio/microsoft_teams/delegated_token`) with configurable pre-expiry silent refresh. CLI command: `legion auth teams`. Hook route: `GET|POST /api/hooks/lex/microsoft_teams/auth/callback` for daemon re-auth (routed through Ingress for RBAC/audit).

Key files: `Helpers::BrowserAuth` (orchestrator), `Helpers::CallbackServer` (ephemeral TCP), `Runners::Auth` (authorize_url, exchange_code, refresh_delegated_token, auth_callback), `Helpers::TokenCache` (delegated slot), `Hooks::Auth` (hook class with mount path).

## Token Lifecycle (v0.5.4)

Automatic delegated token management: validate on boot, refresh on a timer, re-authenticate via browser when a previously authenticated user's token expires.

- **AuthValidator** (Once actor, 2s delay): Loads token from Vault/local file on boot, attempts refresh. If refresh fails and user previously authenticated (`previously_authenticated?` — local file exists), fires BrowserAuth. Silent for users who never opted in.
- **TokenRefresher** (Every actor, 15min default): Guards with `authenticated?` (live token in memory). Refreshes and persists on each tick. On failure, same re-auth logic as AuthValidator.
- **TokenCache predicates**: `authenticated?` = live token in `@delegated_cache`. `previously_authenticated?` = local token file exists on disk. This distinction controls auto re-auth (returning users only) vs silence (never-authenticated users).

Configuration: `settings[:microsoft_teams][:auth][:delegated][:refresh_interval]` (default 900 seconds).

Design doc: `docs/plans/2026-03-19-teams-token-lifecycle-design.md`

## AI Bot (v0.2.0)

Two operating modes, both using polling (Graph API) with AMQP-based message routing:

### Mode 1: Direct Chat
User DMs the bot 1:1. Bot responds via legion-llm with multi-turn session context.

```
DirectChatPoller (5s) → AMQP exchange → MessageProcessor → Bot::handle_message
  → SessionManager.get_or_create → llm_session.ask(text) → Graph API reply
```

### Mode 2: Conversation Observer
User subscribes the bot to watch a human 1:1 conversation. Bot passively extracts tasks, context, and relationship data.

```
ObservedChatPoller (30s) → AMQP exchange → MessageProcessor → Bot::observe_message
  → LLM extraction → lex-memory episodic trace → optional notification to owner
```

**Observer is disabled by default** (`settings[:bot][:observe][:enabled] = false`). Compliance gate — must be explicitly enabled.

### Message Flow

Both pollers publish to the same `teams.messages` AMQP exchange. The MessageProcessor subscription actor consumes from the queue and routes by `mode` field (`:direct` → `handle_message`, `:observe` → `observe_message`). This architecture supports a future webhook path: a `POST /api/hooks/microsoft_teams/bot` endpoint would publish to the same exchange with zero runner changes.

### Configuration

Layered config cascade in `Legion::Settings[:microsoft_teams]`:

```yaml
microsoft_teams:
  auth:
    tenant_id: "..."
    client_id: "..."
    client_secret: "vault://secret/teams/client_secret"
    delegated:
      refresh_interval: 900    # seconds (TokenRefresher interval)
  bot:
    bot_id: "28:your-bot-id"
    direct_poll_interval: 5      # seconds
    observe_poll_interval: 30    # seconds
    system_prompt: "You are a helpful assistant."
    direct:
      system_prompt: ~           # nil = inherit base
    observe:
      enabled: false             # compliance gate
      notify: false              # DM notifications for action items
      system_prompt: "Extract action items. Return structured JSON."
    llm:
      model: ~                   # nil = use legion-llm router
      intent:
        capability: moderate
    session:
      flush_threshold: 20        # messages before auto-persist
      idle_timeout: 900          # seconds (15 min)
      max_recent_messages: 5     # kept raw on persist
```

Per-conversation overrides stored in lex-memory (system_prompt_append, llm model/intent).

### Key Design Decisions

- **Polling first, webhook later**: All connections outbound from user's local LegionIO instance. No public endpoint needed.
- **AMQP-first routing**: Pollers and future webhooks publish to the same exchange. Decouples ingestion from processing.
- **High-water marks**: Per-chat last-seen timestamp in legion-cache prevents reprocessing. Falls back to in-memory when cache unavailable.
- **Session persistence**: Multi-turn sessions flush to lex-memory on threshold (20 msgs), idle timeout (15 min), or shutdown. Restored on restart via summary + recent messages.
- **Token caching**: In-memory OAuth token cache refreshes 60 seconds before expiry. Both pollers share a `TokenCache` instance instead of hitting OAuth every cycle.
- **Subscription registry**: In-memory working set of observed conversations, persisted to lex-memory on change. No legion-data migration needed.
- **Design docs**: `docs/work/completed/2026-03-15-teams-ai-bot-design.md`, `docs/work/completed/2026-03-15-teams-bot-commands-design.md`

### Bot Commands (v0.3.0)

Keyword-based command detection in bot DMs, checked before LLM response:

| Command | Action |
|---------|--------|
| `watch <name>` | Find chat via Graph API, subscribe to observe |
| `stop watching <name>` / `unwatch <name>` | Unsubscribe |
| `watching` / `list` / `subscriptions` | List active subscriptions |
| `pause <name>` | Disable subscription temporarily |
| `resume <name>` | Re-enable paused subscription |
| `prefer <value>` | Set preference (concise, detailed, formal, casual, etc.) |
| `preferences` / `my preferences` | Show current resolved preferences |
| `reset preferences` | Clear explicit preferences, fall back to observed/defaults |
| anything else | LLM response (existing flow) |

## API Surface

Four distinct APIs accessed via Faraday + one local data source:
- **Microsoft Graph API** (`graph.microsoft.com/v1.0`) — chats, channels, messages, teams, subscriptions, presence
- **Bot Framework Service** (`service_url` per conversation) — send activities, create conversations
- **Entra ID OAuth** (`login.microsoftonline.com`) — client_credentials token acquisition
- **Local LevelDB Cache** (Chromium IndexedDB) — offline message extraction from Teams 2.x local storage

## Graph API Permissions Required

| Permission | Type | Purpose |
|-----------|------|---------|
| `Chat.Read.All` | Application | Read chat messages |
| `Chat.ReadWrite.All` | Application | Send chat messages |
| `ChannelMessage.Read.All` | Application | Read channel messages |
| `ChannelMessage.Send` | Delegated | Send channel messages |
| `Team.ReadBasic.All` | Application | List teams and members |
| `Channel.ReadBasic.All` | Application | List channels |
| `Presence.Read.All` | Application | Read user presence |
| `OnlineMeetings.Read` | Delegated | Read online meetings (user context) |
| `OnlineMeetings.Read.All` | Application | Read online meetings |
| `OnlineMeetingTranscript.Read.All` | Application/Delegated | Read meeting transcripts |

For bot scenarios, register the Entra app as a Teams Bot via Bot Framework portal.

## Dependencies

| Gem | Purpose |
|-----|---------|
| `faraday` (>= 2.0) | HTTP client for Graph API, Bot Framework, and OAuth |
| `snappy` (>= 0.5) | Snappy decompression for LevelDB SSTable blocks |
| `base64` (>= 0.1) | Base64 encoding for PKCE (removed from Ruby 3.4 default gems) |

Optional framework dependencies (guarded with `defined?`, not in gemspec):
- `legion-transport` — AMQP exchange/queue/message for bot message routing
- `legion-llm` — LLM routing for bot responses (`llm_chat`, `llm_session`)
- `legion-cache` — High-water mark storage for message dedup
- `lex-memory` — Session persistence and episodic trace storage
- `lex-mesh` — PreferenceProfile for per-user preference resolution

## Testing

```bash
bundle install
bundle exec rspec     # 223 specs across 31 spec files (as of v0.5.6)
bundle exec rubocop   # Clean
```

---

**Maintained By**: Matthew Iverson (@Esity)
