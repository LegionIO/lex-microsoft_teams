# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Messages
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_chat_messages(chat_id:, top: 50, **)
            params = { '$top' => top }
            response = graph_connection(**).get("chats/#{chat_id}/messages", params)
            { result: response.body }
          end

          def get_chat_message(chat_id:, message_id:, **)
            response = graph_connection(**).get("chats/#{chat_id}/messages/#{message_id}")
            { result: response.body }
          end

          def send_chat_message(chat_id:, content:, content_type: 'text', attachments: [], **)
            payload = { body: { contentType: content_type, content: content } }
            payload[:attachments] = attachments unless attachments.empty?
            response = graph_connection(**).post("chats/#{chat_id}/messages", payload)
            { result: response.body }
          end

          def reply_to_chat_message(chat_id:, message_id:, content:, content_type: 'text', **)
            payload = { body: { contentType: content_type, content: content } }
            response = graph_connection(**).post("chats/#{chat_id}/messages/#{message_id}/replies", payload)
            { result: response.body }
          end

          def list_message_replies(chat_id:, message_id:, top: 50, **)
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
