# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Chats
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_chats(user_id: 'me', top: 50, **)
            params = { '$top' => top }
            response = graph_connection(**).get("/#{user_id}/chats", params)
            { result: response.body }
          end

          def get_chat(chat_id:, **)
            response = graph_connection(**).get("/chats/#{chat_id}")
            { result: response.body }
          end

          def create_chat(members:, chat_type: 'oneOnOne', topic: nil, **)
            payload = { chatType: chat_type, members: members }
            payload[:topic] = topic if topic
            response = graph_connection(**).post('/chats', payload)
            { result: response.body }
          end

          def list_chat_members(chat_id:, **)
            response = graph_connection(**).get("/chats/#{chat_id}/members")
            { result: response.body }
          end

          def add_chat_member(chat_id:, user_id:, roles: ['owner'], **)
            payload = {
              '@odata.type'     => '#microsoft.graph.aadUserConversationMember',
              'roles'           => roles,
              'user@odata.bind' => "https://graph.microsoft.com/v1.0/users('#{user_id}')"
            }
            response = graph_connection(**).post("/chats/#{chat_id}/members", payload)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
