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
                     desc:          'List messages in a Teams chat thread with pagination, ordering, and filtering',
                     mcp_prefix:    'teams.list_chat_messages',
                     mcp_category:  'teams_messages',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { chat_id:   { type:        'string',
                                                                 description: 'Teams chat ID' },
                                                    top:       { type:        'integer',
                                                                 description: 'Messages per page (default 50, max 50)' },
                                                    max_pages: { type:        'integer',
                                                                 description: 'Maximum pages to fetch (default 1)' },
                                                    orderby:   { type:        'string',
                                                                 description: 'Sort order: lastModifiedDateTime desc or createdDateTime desc' },
                                                    filter:    { type:        'string',
                                                                 description: 'OData $filter on lastModifiedDateTime or createdDateTime' } },
                                      required:   ['chat_id'] },
                     trigger_words: %w[messages history read]

          def list_chat_messages(chat_id:, top: 50, max_pages: 1, orderby: nil, filter: nil, **)
            log.debug "list_chat_messages(chat_id: #{chat_id}, top: #{top}, max_pages: #{max_pages})"
            per_page = [top, 50].min
            params = { '$top' => per_page }
            params['$orderby'] = orderby if orderby
            params['$filter'] = filter if filter
            conn = graph_connection(**)
            response = conn.get("chats/#{chat_id}/messages", params)
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
                     desc:          'List replies to a message in a Teams chat with pagination support',
                     mcp_prefix:    'teams.list_message_replies',
                     mcp_category:  'teams_messages',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { chat_id:    { type: 'string' },
                                                    message_id: { type: 'string' },
                                                    top:        { type:        'integer',
                                                                  description: 'Number of replies to return per page (default 50)' },
                                                    max_pages:  { type:        'integer',
                                                                  description: 'Maximum pages to fetch (default 1)' } },
                                      required:   %w[chat_id message_id] },
                     trigger_words: %w[replies thread]

          def list_message_replies(chat_id:, message_id:, top: 50, max_pages: 1, **)
            log.debug "list_message_replies(chat_id: #{chat_id}, message_id: #{message_id}, top: #{top}, max_pages: #{max_pages})"
            per_page = [top, 50].min
            params = { '$top' => per_page }
            conn = graph_connection(**)
            response = conn.get("chats/#{chat_id}/messages/#{message_id}/replies", params)
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

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
