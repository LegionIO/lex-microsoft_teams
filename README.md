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

### Subscriptions (Change Notifications)
- `list_subscriptions` — List active subscriptions
- `get_subscription` — Get subscription details
- `create_subscription` — Create a change notification subscription
- `renew_subscription` — Extend subscription expiration
- `delete_subscription` — Delete a subscription
- `subscribe_to_chat_messages` — Subscribe to chat message events
- `subscribe_to_channel_messages` — Subscribe to channel message events

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

## Standalone Client

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
```

## Requirements

- Ruby >= 3.4
- [LegionIO](https://github.com/LegionIO/LegionIO) framework
- Microsoft Entra ID application with appropriate Graph API permissions

## License

MIT
