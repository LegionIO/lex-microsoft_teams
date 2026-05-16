# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Chats
          extend Legion::Extensions::Definitions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[chat chats conversation conversations dm direct]
          end

          definition :list_chats,
                     desc:          'List Teams chats for the current user',
                     mcp_prefix:    'teams.list_chats',
                     mcp_category:  'teams_chat',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     trigger_words: %w[chats conversations]

          def list_chats(user_id: 'me', top: 50, **)
            params = { '$top' => top }
            response = graph_connection(**).get("#{user_path(user_id)}/chats", params)
            { result: response.body }
          end

          definition :get_chat,
                     desc:          'Get metadata for a specific Teams chat by ID',
                     mcp_prefix:    'teams.get_chat',
                     mcp_category:  'teams_chat',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { chat_id: { type:        'string',
                                                               description: 'The Teams chat ID (19:...@thread.v2)' } },
                                      required:   ['chat_id'] },
                     trigger_words: %w[chat details]

          def get_chat(chat_id:, **)
            response = graph_connection(**).get("chats/#{chat_id}")
            { result: response.body }
          end

          definition :create_chat,
                     desc:          'Create a new 1:1 or group Teams chat',
                     mcp_prefix:    'teams.create_chat',
                     mcp_category:  'teams_chat',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { members:   { type:        'array',
                                                                 description: 'Array of user IDs or UPNs' },
                                                    chat_type: { type:        'string',
                                                                 description: 'oneOnOne or group' } },
                                      required:   ['members'] },
                     trigger_words: %w[create conversation start]

          def create_chat(members:, chat_type: 'oneOnOne', topic: nil, **)
            payload = { chatType: chat_type, members: members }
            payload[:topic] = topic if topic
            response = graph_connection(**).post('chats', payload)
            { result: response.body }
          end

          definition :list_chat_members,
                     desc:          'List members of a Teams chat',
                     mcp_prefix:    'teams.list_chat_members',
                     mcp_category:  'teams_chat',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { chat_id: { type: 'string' } }, required: ['chat_id'] },
                     trigger_words: %w[members participants]

          def list_chat_members(chat_id:, **)
            response = graph_connection(**).get("chats/#{chat_id}/members")
            { result: response.body }
          end

          definition :add_chat_member,
                     desc:          'Add a member to a Teams chat',
                     mcp_prefix:    'teams.add_chat_member',
                     mcp_category:  'teams_chat',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { chat_id: { type: 'string' },
                                                    user_id: { type: 'string' } },
                                      required:   %w[chat_id user_id] },
                     trigger_words: %w[invite add member]

          def add_chat_member(chat_id:, user_id:, roles: ['owner'], **)
            payload = {
              '@odata.type'     => '#microsoft.graph.aadUserConversationMember',
              'roles'           => roles,
              'user@odata.bind' => "https://graph.microsoft.com/v1.0/users('#{user_id}')"
            }
            response = graph_connection(**).post("chats/#{chat_id}/members", payload)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
