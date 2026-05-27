# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module ChannelMessages
          extend Legion::Extensions::Definitions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[post posts feed thread reply]
          end

          definition :list_channel_messages,
                     desc:          'List messages posted in a Teams channel with pagination and expand support',
                     mcp_prefix:    'teams.list_channel_messages',
                     mcp_category:  'teams_channel_messages',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' },
                                                    top:        { type:        'integer',
                                                                  description: 'Messages per page (default 20, max 50)' },
                                                    max_pages:  { type:        'integer',
                                                                  description: 'Maximum pages to fetch (default 1)' },
                                                    expand:     { type:        'string',
                                                                  description: 'Expand related entities (e.g. replies)' } },
                                      required:   %w[team_id channel_id] },
                     trigger_words: %w[channel history posts feed]

          def list_channel_messages(team_id:, channel_id:, top: 50, max_pages: 1, expand: nil, **)
            per_page = [top, 50].min
            params = { '$top' => per_page }
            params['$expand'] = expand if expand
            conn = graph_connection(**)
            response = conn.get("teams/#{team_id}/channels/#{channel_id}/messages", params)
            body = response.body

            return { result: body } if max_pages <= 1

            all_values = Array(body['value'] || body[:value])
            next_link = body['@odata.nextLink'] || body[:'@odata.nextLink']
            pages_fetched = 1

            while next_link && pages_fetched < max_pages
              response = conn.get(next_link)
              page_body = response.body
              items = page_body['value'] || page_body[:value]
              all_values.concat(Array(items)) if items
              next_link = page_body['@odata.nextLink'] || page_body[:'@odata.nextLink']
              pages_fetched += 1
            end

            result = { '@odata.context' => body['@odata.context'] || body[:'@odata.context'],
                       'value'          => all_values }
            result['@odata.nextLink'] = next_link if next_link
            { result: result }
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
                     trigger_words: %w[message fetch]

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
                     trigger_words: %w[post send write]

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
                     trigger_words: %w[reply respond]

          def reply_to_channel_message(team_id:, channel_id:, message_id:, content:, content_type: 'text', **)
            payload = { body: { contentType: content_type, content: content } }
            response = graph_connection(**).post(
              "teams/#{team_id}/channels/#{channel_id}/messages/#{message_id}/replies", payload
            )
            { result: response.body }
          end

          definition :list_channel_message_replies,
                     desc:          'List replies in a Teams channel message thread with pagination',
                     mcp_prefix:    'teams.list_channel_message_replies',
                     mcp_category:  'teams_channel_messages',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { team_id:    { type: 'string' },
                                                    channel_id: { type: 'string' },
                                                    message_id: { type: 'string' },
                                                    top:        { type:        'integer',
                                                                  description: 'Replies per page (default 50, max 50)' },
                                                    max_pages:  { type:        'integer',
                                                                  description: 'Maximum pages to fetch (default 1)' } },
                                      required:   %w[team_id channel_id message_id] },
                     trigger_words: %w[replies thread]

          def list_channel_message_replies(team_id:, channel_id:, message_id:, top: 50, max_pages: 1, **)
            per_page = [top, 50].min
            params = { '$top' => per_page }
            conn = graph_connection(**)
            response = conn.get(
              "teams/#{team_id}/channels/#{channel_id}/messages/#{message_id}/replies", params
            )
            body = response.body

            return { result: body } if max_pages <= 1

            all_values = Array(body['value'] || body[:value])
            next_link = body['@odata.nextLink'] || body[:'@odata.nextLink']
            pages_fetched = 1

            while next_link && pages_fetched < max_pages
              response = conn.get(next_link)
              page_body = response.body
              items = page_body['value'] || page_body[:value]
              all_values.concat(Array(items)) if items
              next_link = page_body['@odata.nextLink'] || page_body[:'@odata.nextLink']
              pages_fetched += 1
            end

            result = { '@odata.context' => body['@odata.context'] || body[:'@odata.context'],
                       'value'          => all_values }
            result['@odata.nextLink'] = next_link if next_link
            { result: result }
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
                     trigger_words: %w[edit update]

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
