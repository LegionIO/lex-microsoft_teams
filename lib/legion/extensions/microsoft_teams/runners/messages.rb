# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Messages
          extend Legion::Extensions::Definitions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[message messages reply replies thread send]
          end

          definition :list_chat_messages,
                     desc:          'List messages in a Teams chat thread',
                     mcp_prefix:    'teams.list_chat_messages',
                     mcp_category:  'teams_messages',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { chat_id: { type:        'string',
                                                               description: 'Teams chat ID' } },
                                      required:   ['chat_id'] },
                     trigger_words: %w[messages history read]

          def list_chat_messages(chat_id:, top: 50, **)
            log.debug "list_chat_messages(chat_id: #{chat_id}, top: #{top})"
            params = { '$top' => top }
            response = graph_connection(**).get("chats/#{chat_id}/messages", params)
            { result: response.body }
          end

          definition :get_chat_message,
                     desc:          'Get a specific message from a Teams chat',
                     mcp_prefix:    'teams.get_chat_message',
                     mcp_category:  'teams_messages',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { chat_id:    { type: 'string' },
                                                    message_id: { type: 'string' } },
                                      required:   %w[chat_id message_id] },
                     trigger_words: %w[message fetch]

          def get_chat_message(chat_id:, message_id:, **)
            log.debug "get_chat_message(chat_id: #{chat_id}, message_id: #{message_id})"
            response = graph_connection(**).get("chats/#{chat_id}/messages/#{message_id}")
            { result: response.body }
          end

          definition :send_chat_message,
                     desc:          'Send a message to a Teams chat',
                     mcp_prefix:    'teams.send_chat_message',
                     mcp_category:  'teams_messages',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { chat_id: { type: 'string' },
                                                    content: { type:        'string',
                                                               description: 'Message text or HTML' } },
                                      required:   %w[chat_id content] },
                     trigger_words: %w[send post write]

          def send_chat_message(chat_id:, content:, content_type: 'text', attachments: [], **)
            log.debug "send_chat_message(chat_id: #{chat_id}, content: #{content}, content_type: #{content_type})"
            payload = { body: { contentType: content_type, content: content } }
            payload[:attachments] = attachments unless attachments.empty?
            response = graph_connection(**).post("chats/#{chat_id}/messages", payload)
            { result: response.body }
          end

          definition :reply_to_chat_message,
                     desc:          'Reply to a message in a Teams chat',
                     mcp_prefix:    'teams.reply_to_chat_message',
                     mcp_category:  'teams_messages',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { chat_id:    { type: 'string' },
                                                    message_id: { type: 'string' },
                                                    content:    { type: 'string' } },
                                      required:   %w[chat_id message_id content] },
                     trigger_words: %w[reply respond]

          def reply_to_chat_message(chat_id:, message_id:, content:, content_type: 'text', **)
            log.debug "reply_to_chat_message(chat_id: #{chat_id}, message_id: #{message_id}, content: #{content}, content_type: #{content_type})"
            payload = { body: { contentType: content_type, content: content } }
            response = graph_connection(**).post("chats/#{chat_id}/messages/#{message_id}/replies", payload)
            { result: response.body }
          end

          definition :list_message_replies,
                     desc:          'List replies to a message in a Teams chat',
                     mcp_prefix:    'teams.list_message_replies',
                     mcp_category:  'teams_messages',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { chat_id:    { type: 'string' },
                                                    message_id: { type: 'string' } },
                                      required:   %w[chat_id message_id] },
                     trigger_words: %w[replies thread]

          def list_message_replies(chat_id:, message_id:, top: 50, **)
            log.debug "list_message_replies(chat_id: #{chat_id}, message_id: #{message_id}, top: #{top})"
            params = { '$top' => top }
            response = graph_connection(**).get("chats/#{chat_id}/messages/#{message_id}/replies", params)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
