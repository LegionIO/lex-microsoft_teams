# Changelog

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
