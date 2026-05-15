# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module ChannelMessages
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            ['channel message', 'channel messages', 'channel post']
          end

          definition :list_channel_messages,
                     desc:          'List messages posted in a Teams channel',
                     mcp_prefix:    'teams.list_channel_messages',
                     mcp_category:  'teams_channel_messages',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' } },
                                      required:   %w[team_id channel_id] },
                     trigger_words: ['read channel', 'channel history', 'channel posts', 'channel feed']

          def list_channel_messages(team_id:, channel_id:, top: 50, **)
            params = { '$top' => top }
            response = graph_connection(**).get("teams/#{team_id}/channels/#{channel_id}/messages", params)
            { result: response.body }
          end

          definition :get_channel_message,
                     desc:          'Get a specific message from a Teams channel',
                     mcp_prefix:    'teams.get_channel_message',
                     mcp_category:  'teams_channel_messages',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' },
                                                    message_id: { type: 'string' } },
                                      required:   %w[team_id channel_id message_id] },
                     trigger_words: ['get channel message']

          def get_channel_message(team_id:, channel_id:, message_id:, **)
            response = graph_connection(**).get("teams/#{team_id}/channels/#{channel_id}/messages/#{message_id}")
            { result: response.body }
          end

          definition :send_channel_message,
                     desc:          'Post a message to a Teams channel',
                     mcp_prefix:    'teams.send_channel_message',
                     mcp_category:  'teams_channel_messages',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' },
                                                    content:    { type: 'string' } },
                                      required:   %w[team_id channel_id content] },
                     trigger_words: ['post to channel', 'post message', 'send to channel']

          def send_channel_message(team_id:, channel_id:, content:, content_type: 'text', attachments: [], **)
            payload = { body: { contentType: content_type, content: content } }
            payload[:attachments] = attachments unless attachments.empty?
            response = graph_connection(**).post("teams/#{team_id}/channels/#{channel_id}/messages", payload)
            { result: response.body }
          end

          definition :reply_to_channel_message,
                     desc:          'Reply to a thread in a Teams channel',
                     mcp_prefix:    'teams.reply_to_channel_message',
                     mcp_category:  'teams_channel_messages',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' },
                                                    message_id: { type: 'string' },
                                                    content:    { type: 'string' } },
                                      required:   %w[team_id channel_id message_id content] },
                     trigger_words: ['reply in channel', 'channel reply']

          def reply_to_channel_message(team_id:, channel_id:, message_id:, content:, content_type: 'text', **)
            payload = { body: { contentType: content_type, content: content } }
            response = graph_connection(**).post(
              "teams/#{team_id}/channels/#{channel_id}/messages/#{message_id}/replies", payload
            )
            { result: response.body }
          end

          definition :list_channel_message_replies,
                     desc:          'List replies in a Teams channel message thread',
                     mcp_prefix:    'teams.list_channel_message_replies',
                     mcp_category:  'teams_channel_messages',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' },
                                                    message_id: { type: 'string' } },
                                      required:   %w[team_id channel_id message_id] },
                     trigger_words: ['channel thread', 'channel replies']

          def list_channel_message_replies(team_id:, channel_id:, message_id:, top: 50, **)
            params = { '$top' => top }
            response = graph_connection(**).get(
              "teams/#{team_id}/channels/#{channel_id}/messages/#{message_id}/replies", params
            )
            { result: response.body }
          end

          definition :edit_channel_message,
                     desc:          'Edit an existing message in a Teams channel',
                     mcp_prefix:    'teams.edit_channel_message',
                     mcp_category:  'teams_channel_messages',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' },
                                                    message_id: { type: 'string' },
                                                    content:    { type: 'string' } },
                                      required:   %w[team_id channel_id message_id content] },
                     trigger_words: ['edit message', 'update message']

          def edit_channel_message(team_id:, channel_id:, message_id:, content:, content_type: 'text', **)
            payload = { body: { contentType: content_type, content: content } }
            response = graph_connection(**).patch(
              "teams/#{team_id}/channels/#{channel_id}/messages/#{message_id}", payload
            )
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
