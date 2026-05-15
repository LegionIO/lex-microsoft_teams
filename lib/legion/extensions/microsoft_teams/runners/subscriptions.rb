# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Subscriptions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[subscription subscriptions webhook webhooks subscribe watch]
          end

          definition :list_subscriptions,
                     desc:          'List active Graph API subscriptions',
                     mcp_prefix:    'teams.list_subscriptions',
                     mcp_category:  'teams_subscriptions',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     trigger_words: %w[subscriptions webhooks]

          def list_subscriptions(**)
            response = graph_connection(**).get('subscriptions')
            { result: response.body }
          end

          definition :get_subscription,
                     desc:          'Get a specific Graph API subscription',
                     mcp_prefix:    'teams.get_subscription',
                     mcp_category:  'teams_subscriptions',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { subscription_id: { type: 'string' } },
                                      required:   ['subscription_id'] },
                     trigger_words: %w[subscription webhook]

          def get_subscription(subscription_id:, **)
            response = graph_connection(**).get("subscriptions/#{subscription_id}")
            { result: response.body }
          end

          definition :create_subscription,
                     desc:          'Create a new Graph API change notification subscription',
                     mcp_prefix:    'teams.create_subscription',
                     mcp_category:  'teams_subscriptions',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { resource:         { type:        'string',
                                                                        description: 'Graph resource path to subscribe to' },
                                                    change_type:      { type:        'string',
                                                                        description: 'created, updated, deleted' },
                                                    notification_url: { type:        'string',
                                                                        description: 'HTTPS webhook URL' },
                                                    expiration:       { type:        'string',
                                                                        description: 'ISO 8601 expiration datetime' } },
                                      required:   %w[resource change_type notification_url expiration] },
                     trigger_words: %w[subscribe webhook create]

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
            response = graph_connection(**).post('subscriptions', payload)
            { result: response.body }
          end

          definition :renew_subscription,
                     desc:          'Renew an expiring Graph API subscription',
                     mcp_prefix:    'teams.renew_subscription',
                     mcp_category:  'teams_subscriptions',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { subscription_id: { type: 'string' },
                                                    expiration:      { type:        'string',
                                                                       description: 'New ISO 8601 expiration datetime' } },
                                      required:   %w[subscription_id expiration] },
                     trigger_words: %w[renew extend]

          def renew_subscription(subscription_id:, expiration:, **)
            payload = { expirationDateTime: expiration }
            response = graph_connection(**).patch("subscriptions/#{subscription_id}", payload)
            { result: response.body }
          end

          definition :delete_subscription,
                     desc:          'Delete a Graph API subscription',
                     mcp_prefix:    'teams.delete_subscription',
                     mcp_category:  'teams_subscriptions',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { subscription_id: { type: 'string' } },
                                      required:   ['subscription_id'] },
                     trigger_words: %w[unsubscribe delete]

          def delete_subscription(subscription_id:, **)
            response = graph_connection(**).delete("subscriptions/#{subscription_id}")
            { result: response.body }
          end

          definition :subscribe_to_chat_messages,
                     desc:          'Subscribe to new and updated messages in a Teams chat',
                     mcp_prefix:    'teams.subscribe_to_chat_messages',
                     mcp_category:  'teams_subscriptions',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { chat_id:          { type: 'string' },
                                                    notification_url: { type: 'string' },
                                                    expiration:       { type: 'string' } },
                                      required:   %w[chat_id notification_url expiration] },
                     trigger_words: %w[subscribe watch chat]

          def subscribe_to_chat_messages(chat_id:, notification_url:, expiration:, client_state: nil, **)
            create_subscription(
              resource:         "/chats/#{chat_id}/messages",
              change_type:      'created,updated',
              notification_url: notification_url,
              expiration:       expiration,
              client_state:     client_state,
              **
            )
          end

          definition :subscribe_to_channel_messages,
                     desc:          'Subscribe to new and updated messages in a Teams channel',
                     mcp_prefix:    'teams.subscribe_to_channel_messages',
                     mcp_category:  'teams_subscriptions',
                     mcp_tier:      :elevated,
                     idempotent:    false,
                     inputs:        { properties: { team_id:          { type: 'string' },
                                                    channel_id:       { type: 'string' },
                                                    notification_url: { type: 'string' },
                                                    expiration:       { type: 'string' } },
                                      required:   %w[team_id channel_id notification_url expiration] },
                     trigger_words: %w[subscribe watch channel]

          def subscribe_to_channel_messages(team_id:, channel_id:, notification_url:, expiration:,
                                            client_state: nil, **)
            create_subscription(
              resource:         "/teams/#{team_id}/channels/#{channel_id}/messages",
              change_type:      'created,updated',
              notification_url: notification_url,
              expiration:       expiration,
              client_state:     client_state,
              **
            )
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
