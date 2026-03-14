# lex-microsoft_teams: Microsoft Teams Integration for LegionIO

**Repository Level 3 Documentation**
- **Parent (Level 2)**: `/Users/miverso2/rubymine/legion/extensions/CLAUDE.md`
- **Parent (Level 1)**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Legion Extension that connects LegionIO to Microsoft Teams via Graph API and Bot Framework. Provides runners for chats, channels, messages, subscriptions (change notifications), adaptive cards, and bot communication.

**GitHub**: https://github.com/LegionIO/lex-microsoft_teams
**License**: MIT

## Architecture

```
Legion::Extensions::MicrosoftTeams
├── Runners/
│   ├── Auth              # OAuth2 client credentials (Graph + Bot Framework)
│   ├── Teams             # List/get teams, members
│   ├── Chats             # 1:1 and group chat CRUD
│   ├── Messages          # Chat message send/read/reply
│   ├── Channels          # Team channel CRUD
│   ├── ChannelMessages   # Channel message send/read/reply
│   ├── Subscriptions     # Graph change notification webhooks
│   ├── AdaptiveCards      # Adaptive Card payload builder
│   └── Bot               # Bot Framework activity send/reply
├── Helpers/
│   └── Client            # Three connection builders (Graph, Bot, OAuth)
└── Client                # Standalone client (includes all runners)
```

## API Surface

Three distinct APIs accessed via Faraday:
- **Microsoft Graph API** (`graph.microsoft.com/v1.0`) — chats, channels, messages, teams, subscriptions
- **Bot Framework Service** (`service_url` per conversation) — send activities, create conversations
- **Entra ID OAuth** (`login.microsoftonline.com`) — client_credentials token acquisition

## Graph API Permissions Required

| Permission | Type | Purpose |
|-----------|------|---------|
| `Chat.Read.All` | Application | Read chat messages |
| `Chat.ReadWrite.All` | Application | Send chat messages |
| `ChannelMessage.Read.All` | Application | Read channel messages |
| `ChannelMessage.Send` | Delegated | Send channel messages |
| `Team.ReadBasic.All` | Application | List teams and members |
| `Channel.ReadBasic.All` | Application | List channels |

For bot scenarios, register the Entra app as a Teams Bot via Bot Framework portal.

## Dependencies

| Gem | Purpose |
|-----|---------|
| `faraday` (>= 2.0) | HTTP client for Graph API, Bot Framework, and OAuth |

## Testing

```bash
bundle install
bundle exec rspec     # 51 specs
bundle exec rubocop   # Clean
```

---

**Maintained By**: Matthew Iverson (@Esity)
