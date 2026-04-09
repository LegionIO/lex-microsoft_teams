# lex-microsoft_teams

Microsoft Teams integration for [LegionIO](https://github.com/LegionIO/LegionIO). Connects to Microsoft Teams via Graph API and Bot Framework for chat, channel, and bot communication.

## Installation

```bash
gem install lex-microsoft_teams
```

## Functions

### Auth
- `acquire_token` — OAuth2 client credentials token for Graph API
- `acquire_bot_token` — OAuth2 token for Bot Framework
- `authorize_url` — Build Authorization Code + PKCE authorize URL for delegated consent
- `exchange_code` — Exchange authorization code for delegated access/refresh tokens
- `refresh_delegated_token` — Refresh a delegated token using a refresh token
- `request_device_code` — Start Device Code flow (headless fallback)
- `poll_device_code` — Poll for Device Code completion (RFC 8628 compliant)

### Teams
- `list_joined_teams` — List teams the user has joined
- `get_team` — Get team details
- `list_team_members` — List members of a team

### Chats
- `list_chats` — List 1:1 and group chats
- `get_chat` — Get chat details
- `create_chat` — Create a new chat
- `list_chat_members` — List chat participants
- `add_chat_member` — Add a member to a chat

### Messages
- `list_chat_messages` — List messages in a chat
- `get_chat_message` — Get a specific message
- `send_chat_message` — Send a message to a chat
- `reply_to_chat_message` — Reply to a message
- `list_message_replies` — List replies to a message

### Channels
- `list_channels` — List channels in a team
- `get_channel` — Get channel details
- `create_channel` — Create a new channel
- `update_channel` — Update channel properties
- `delete_channel` — Delete a channel
- `list_channel_members` — List channel members

### Channel Messages
- `list_channel_messages` — List messages in a channel
- `get_channel_message` — Get a specific channel message
- `send_channel_message` — Send a message to a channel
- `reply_to_channel_message` — Reply to a channel message
- `list_channel_message_replies` — List replies to a channel message

### Meetings
- `list_meetings` — List online meetings for a user
- `get_meeting` — Get meeting details
- `create_meeting` — Create an online meeting
- `update_meeting` — Update meeting properties
- `delete_meeting` — Delete a meeting
- `get_meeting_by_join_url` — Find a meeting by its join URL
- `list_attendance_reports` — List attendance reports for a meeting
- `get_attendance_report` — Get a specific attendance report with attendee records

### Transcripts
- `list_transcripts` — List available transcripts for a meeting
- `get_transcript` — Get transcript metadata
- `get_transcript_content` — Get transcript content (VTT default, DOCX optional via `format:` param)

### Presence
- `get_presence` — Get the availability and activity status for a user

### Subscriptions (Change Notifications)
- `list_subscriptions` — List active subscriptions
- `get_subscription` — Get subscription details
- `create_subscription` — Create a change notification subscription
- `renew_subscription` — Extend subscription expiration
- `delete_subscription` — Delete a subscription
- `subscribe_to_chat_messages` — Subscribe to chat message events
- `subscribe_to_channel_messages` — Subscribe to channel message events

### Local Cache (Offline)
- `extract_local_messages` — Extract messages from the Teams 2.x LevelDB local storage without Graph API credentials
- `local_cache_available?` — Check whether the local Teams cache exists on disk
- `local_cache_stats` — Get message count and date range stats from the local cache without extracting

### Cache Ingest
- `ingest_cache` — Ingest messages from the local Teams cache into lex-memory as episodic traces; returns `{ stored:, skipped:, latest_time: }`

### People
- `get_profile` — Get Graph API profile for a user (default: `/me`)
- `list_people` — List relevant people for a user via `/me/people`

### AI Insights
- `list_meeting_ai_insights` — List AI-generated insights for an online meeting
- `get_meeting_ai_insight` — Get a specific AI insight
- `list_meeting_recordings` — List recordings for an online meeting
- `get_meeting_recording` — Get a specific meeting recording
- `list_call_records` — List call records from Graph API
- `get_call_record` — Get a specific call record

### Ownership
- `sync_owners` — Sync team ownership data from Graph API (single team or all teams)
- `detect_orphans` — Detect teams with no current owners
- `get_team_owners` — Get owners for a specific team

### Adaptive Cards
- `build_card` — Build an Adaptive Card payload
- `text_block` — Create a TextBlock element
- `fact_set` — Create a FactSet element
- `action_open_url` — Create an OpenUrl action
- `action_submit` — Create a Submit action
- `message_attachment` — Wrap a card as a message attachment

### Bot Framework
- `send_activity` — Send an activity to a conversation
- `reply_to_activity` — Reply to an existing activity
- `send_text` — Send a simple text message via bot
- `send_card` — Send an Adaptive Card via bot
- `create_conversation` — Create a new bot conversation
- `get_conversation_members` — List conversation members

### AI Bot (v0.2.0)
- `handle_message` — LLM-powered response loop for direct 1:1 bot chats (polls Graph API, replies via Graph or Bot Framework)
- `observe_message` — Conversation observer that extracts tasks, context, and relationship data from subscribed human chats (disabled by default, compliance-gated)

**Actors:**
- `CacheBulkIngest` — Once at startup: full local LevelDB cache ingest
- `CacheSync` — Every 5min: incremental new-message ingest from local cache
- `DirectChatPoller` — Every 5s: polls bot DM chats via Graph API, publishes to AMQP
- `ObservedChatPoller` — Every 30s: polls subscribed conversations (compliance-gated, disabled by default)
- `MessageProcessor` — AMQP subscription actor, routes messages by mode
- `AuthValidator` — Once at boot: validates and restores delegated tokens
- `TokenRefresher` — Every 15min: keeps delegated tokens fresh
- `ProfileIngest` — Once (5s delay): four-phase cognitive data pipeline after auth
- `ApiIngest` — Every 30min: Graph API ingest with HWM dedup
- `ChannelPoller` — Every 60s: polls joined team channels for new messages
- `MeetingIngest` — Every 5min: polls online meetings, fetches transcripts and AI insights
- `PresencePoller` — Every 60s: polls Graph API presence, logs changes
- `AbsorbMeeting` — Subscription: absorbs Teams meeting data via absorber framework
- `IncrementalSync` — Every 15min: periodic re-sync with HWM dedup

**Helpers:**
- `SessionManager` — Multi-turn LLM session lifecycle with lex-memory persistence
- `PromptResolver` — Layered system prompt resolution (settings default -> mode -> per-conversation -> trace context)
- `HighWaterMark` — Per-chat message deduplication via legion-cache
- `TokenCache` — In-memory OAuth token cache with pre-expiry refresh (app + delegated slots)
- `SubscriptionRegistry` — Conversation observation subscriptions (in-memory + lex-memory)
- `BrowserAuth` — Delegated OAuth orchestrator (PKCE, headless detection, browser launch)
- `CallbackServer` — Ephemeral TCP server for OAuth redirect callback
- `TraceRetriever` — Retrieves and formats memory traces as LLM context (2000-token budget, strength-ranked dedup)

### Delegated Authentication (v0.5.0)

Opt-in browser-based OAuth for delegated Microsoft Graph permissions (e.g., meeting transcripts).

**Authorization Code + PKCE** (primary): Opens the user's browser for Entra ID login, captures the callback on an ephemeral local port, exchanges the code with PKCE verification.

**Device Code** (fallback): Automatically selected in headless/SSH environments (no `DISPLAY`/`WAYLAND_DISPLAY`). Displays a URL and code for the user to enter on any device.

```ruby
# Via CLI
# legion auth teams --tenant-id TENANT --client-id CLIENT

# Via code
auth = Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth.new(
  tenant_id: 'your-tenant-id',
  client_id: 'your-client-id'
)
result = auth.authenticate  # returns token hash with access_token, refresh_token, expires_in
```

Tokens are stored in Vault at a per-user path (`{USER}/microsoft_teams/delegated_token`) and silently refreshed before expiry.

## Standalone Client

The `Client` class includes all runner modules (Auth, Teams, Chats, Messages, Channels, ChannelMessages, Subscriptions, AdaptiveCards, Bot, Presence, Meetings, Transcripts, LocalCache, CacheIngest, People, ProfileIngest, ApiIngest, AiInsights, Ownership).

```ruby
client = Legion::Extensions::MicrosoftTeams::Client.new(
  tenant_id:     'your-tenant-id',
  client_id:     'your-app-id',
  client_secret: 'your-client-secret'
)
client.authenticate!

# Graph API
client.list_chats
client.send_chat_message(chat_id: 'chat-id', content: 'Hello!')

# Bot Framework
client.send_text(
  service_url: 'https://smba.trafficmanager.net/teams/',
  conversation_id: 'conv-id',
  text: 'Hello from bot'
)

# Local cache (no credentials needed)
client.local_cache_available?
client.extract_local_messages(since: Time.now - 86_400)
```

## Requirements

- Ruby >= 3.4
- [LegionIO](https://github.com/LegionIO/LegionIO) framework
- Microsoft Entra ID application with appropriate Graph API permissions

## License

MIT
