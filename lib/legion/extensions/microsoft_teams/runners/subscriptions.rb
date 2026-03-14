# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Subscriptions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_subscriptions(**)
            response = graph_connection(**).get('/subscriptions')
            { result: response.body }
          end

          def get_subscription(subscription_id:, **)
            response = graph_connection(**).get("/subscriptions/#{subscription_id}")
            { result: response.body }
          end

          def create_subscription(resource:, change_type:, notification_url:, expiration:,
                                  client_state: nil, include_resource_data: false, **)
            payload = {
              changeType:          change_type,
              notificationUrl:     notification_url,
              resource:            resource,
              expirationDateTime:  expiration,
              includeResourceData: include_resource_data
            }
            payload[:clientState] = client_state if client_state
            response = graph_connection(**).post('/subscriptions', payload)
            { result: response.body }
          end

          def renew_subscription(subscription_id:, expiration:, **)
            payload = { expirationDateTime: expiration }
            response = graph_connection(**).patch("/subscriptions/#{subscription_id}", payload)
            { result: response.body }
          end

          def delete_subscription(subscription_id:, **)
            response = graph_connection(**).delete("/subscriptions/#{subscription_id}")
            { result: response.body }
          end

          def subscribe_to_chat_messages(chat_id:, notification_url:, expiration:, client_state: nil, **)
            create_subscription(
              resource:            "/chats/#{chat_id}/messages",
              change_type:         'created,updated',
              notification_url:    notification_url,
              expiration:          expiration,
              client_state:        client_state,
              **
            )
          end

          def subscribe_to_channel_messages(team_id:, channel_id:, notification_url:, expiration:,
                                            client_state: nil, **)
            create_subscription(
              resource:            "/teams/#{team_id}/channels/#{channel_id}/messages",
              change_type:         'created,updated',
              notification_url:    notification_url,
              expiration:          expiration,
              client_state:        client_state,
              **
            )
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
