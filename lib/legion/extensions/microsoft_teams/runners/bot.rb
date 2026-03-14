# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Bot
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def send_activity(service_url:, conversation_id:, activity:, **)
            conn = bot_connection(service_url: service_url, **)
            response = conn.post("/v3/conversations/#{conversation_id}/activities", activity)
            { result: response.body }
          end

          def reply_to_activity(service_url:, conversation_id:, activity_id:, text: nil,
                                attachments: [], content_type: 'message', **)
            activity = { type: content_type, text: text }
            activity[:attachments] = attachments unless attachments.empty?
            conn = bot_connection(service_url: service_url, **)
            response = conn.post(
              "/v3/conversations/#{conversation_id}/activities/#{activity_id}", activity
            )
            { result: response.body }
          end

          def send_text(service_url:, conversation_id:, text:, **)
            send_activity(
              service_url:     service_url,
              conversation_id: conversation_id,
              activity:        { type: 'message', text: text },
              **
            )
          end

          def send_card(service_url:, conversation_id:, card:, **)
            attachment = {
              contentType: 'application/vnd.microsoft.card.adaptive',
              contentUrl:  nil,
              content:     card
            }
            send_activity(
              service_url:     service_url,
              conversation_id: conversation_id,
              activity:        { type: 'message', attachments: [attachment] },
              **
            )
          end

          def create_conversation(service_url:, bot_id:, user_id:, tenant_id: nil, **)
            payload = {
              bot:     { id: bot_id },
              members: [{ id: user_id }],
              isGroup: false
            }
            payload[:tenantId] = tenant_id if tenant_id
            conn = bot_connection(service_url: service_url, **)
            response = conn.post('/v3/conversations', payload)
            { result: response.body }
          end

          def get_conversation_members(service_url:, conversation_id:, **)
            conn = bot_connection(service_url: service_url, **)
            response = conn.get("/v3/conversations/#{conversation_id}/members")
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
