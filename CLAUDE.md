# lex-microsoft_teams

Microsoft Teams integration via Graph API and Bot Framework. Provides runners for chats, channels, messages, subscriptions, adaptive cards, bot communication (direct + conversation observer), presence, meetings, transcripts, local cache ingestion, cognitive profile pipeline, and delegated OAuth authentication.

## Architecture

```
Legion::Extensions::MicrosoftTeams
├── Runners/        Auth, Teams, Chats, Messages, Channels, ChannelMessages,
│                   Subscriptions, AdaptiveCards, Bot, Presence, Meetings,
│                   Transcripts, LocalCache, CacheIngest, People, ProfileIngest,
│                   ApiIngest, AiInsights, Ownership
├── Actors/         CacheBulkIngest, CacheSync(5m), DirectChatPoller(5s),
│                   ObservedChatPoller(30s), MessageProcessor, AuthValidator,
│                   TokenRefresher(15m), ProfileIngest, ApiIngest(30m),
│                   ChannelPoller(60s), MeetingIngest(5m), PresencePoller(60s),
│                   AbsorbMeeting, IncrementalSync(15m)
├── Transport/      teams.messages exchange + queue
├── LocalCache/     SSTableReader, RecordParser, Extractor (LevelDB offline)
├── Helpers/        Client, HighWaterMark, PromptResolver, SessionManager,
│                   TokenCache, SubscriptionRegistry, BrowserAuth, CallbackServer,
│                   PermissionGuard, TraceRetriever, TransformDefinitions, GraphClient
├── Hooks/Auth      OAuth callback hook
└── CLI/Auth        `legion lex exec teams auth login/status`
```

## Key Design Decisions

- **Polling first, webhook later**: All connections outbound. No public endpoint needed.
- **AMQP-first routing**: Pollers and future webhooks publish to the same exchange. Decouples ingestion from processing.
- **High-water marks**: Per-chat last-seen timestamp in legion-cache prevents reprocessing.
- **Delegated auth**: Browser-based OAuth (PKCE primary, device code fallback for headless). Tokens stored in Vault with silent refresh.
- **Cognitive pipeline**: Four-phase data ingestion (self, people, conversations, teams/meetings) builds social context after auth.
- **Observer disabled by default**: Compliance gate (`settings[:bot][:observe][:enabled] = false`).
- **Session persistence**: Multi-turn sessions flush to lex-memory on threshold/idle/shutdown.
- **Token lifecycle**: AuthValidator on boot + TokenRefresher every 15min. `authenticated?` vs `previously_authenticated?` controls auto re-auth behavior.
