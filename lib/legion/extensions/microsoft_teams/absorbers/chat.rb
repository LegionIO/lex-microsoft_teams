# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Absorbers
        class Chat < Legion::Extensions::Absorbers::Base
          pattern :url, 'teams.microsoft.com/l/chat/19:*@*'
          pattern :url, 'teams.microsoft.com/l/chat/19:*_*@*'
          description 'Absorbs a Teams chat thread (messages, replies, participants) into Apollo'

          def absorb(url: nil, content: nil, metadata: {}, context: {}) # rubocop:disable Lint/UnusedMethodArgument
            report_progress(message: 'extracting chat id from url')
            chat_id = extract_chat_id(url)
            return { success: false, error: 'could not extract chat id from url' } unless chat_id

            report_progress(message: 'fetching chat metadata', percent: 10)
            chat = resolve_chat(chat_id)
            return { success: false, error: 'could not resolve chat' } unless chat

            topic = chat['topic'] || chat[:topic] || 'untitled chat'
            results = { chat_id: chat_id, topic: topic, chunks: 0 }

            ingest_messages(chat_id, topic, results)
            ingest_members(chat_id, topic, results)

            report_progress(message: 'done', percent: 100)
            results.merge(success: true)
          rescue StandardError => e
            log.error("Chat absorber failed: #{e.message}")
            { success: false, error: e.message }
          end

          private

          def chats_runner
            @chats_runner ||= Object.new.extend(Runners::Chats)
          end

          def messages_runner
            @messages_runner ||= Object.new.extend(Runners::Messages)
          end

          def graph_token
            return @graph_token if defined?(@graph_token)

            @graph_token = begin
              Helpers::TokenCache.instance.cached_delegated_token if defined?(Helpers::TokenCache)
            rescue StandardError => e
              log.warn("graph_token unavailable: #{e.message}")
              nil
            end
          end

          def extract_chat_id(url)
            return nil unless url.is_a?(String)

            # teams.microsoft.com/l/chat/19:XXXXX@unq.gbl.spaces/...
            match = url.match(%r{/l/chat/(19:[^/?#]+)})
            return unless match

            URI.decode_uri_component(match[1])
          rescue StandardError => e
            log.debug("extract_chat_id failed: #{e.message}")
            nil
          end

          def resolve_chat(chat_id)
            response = chats_runner.get_chat(chat_id: chat_id, token: graph_token)
            body = response.is_a?(Hash) ? response[:result] : nil
            return nil unless body.is_a?(Hash) && !body['error'] && !body[:error]

            body
          rescue StandardError => e
            log.warn("resolve_chat failed: #{e.message}")
            nil
          end

          def ingest_messages(chat_id, topic, results)
            report_progress(message: 'fetching messages', percent: 25)
            response = messages_runner.list_chat_messages(chat_id: chat_id, top: 50, token: graph_token)
            body = response.is_a?(Hash) ? response[:result] : nil
            return unless body.is_a?(Hash)

            items = body['value'] || body[:value]
            return unless items.is_a?(Array) && items.any?

            # Filter out system/deleted messages and build a readable transcript
            lines = []
            items.reverse_each do |msg|
              next if msg['messageType'] != 'message' && !msg['messageType'].nil?
              next if msg['deletedDateTime'] || msg[:deletedDateTime]

              sender = msg.dig('from', 'user', 'displayName') ||
                       msg.dig(:from, :user, :displayName) ||
                       'unknown'
              body_content = msg.dig('body', 'content') || msg.dig(:body, :content) || ''
              # Strip HTML tags for plain text
              text = body_content.gsub(/<[^>]+>/, '').strip
              next if text.empty?

              timestamp = msg['createdDateTime'] || msg[:createdDateTime]
              lines << "[#{timestamp}] #{sender}: #{text}"

              # Pull replies for this message
              reply_lines = fetch_reply_lines(chat_id, msg['id'] || msg[:id], topic)
              lines.concat(reply_lines) if reply_lines.any?
            end

            return if lines.empty?

            report_progress(message: 'ingesting message thread', percent: 60)
            absorb_to_knowledge(
              content:      lines.join("\n"),
              tags:         ['teams', 'chat', 'messages', topic],
              source_file:  "teams://chats/#{chat_id}/messages",
              heading:      "Chat: #{topic}",
              content_type: 'teams_chat_thread'
            )
            results[:chunks] += 1
          rescue StandardError => e
            log.warn("Message ingest failed: #{e.message}")
          end

          def fetch_reply_lines(chat_id, message_id, _topic)
            return [] unless message_id

            response = messages_runner.list_message_replies(
              chat_id: chat_id, message_id: message_id, top: 50, token: graph_token
            )
            body  = response.is_a?(Hash) ? response[:result] : nil
            items = body.is_a?(Hash) ? (body['value'] || body[:value]) : nil
            return [] unless items.is_a?(Array) && items.any?

            items.filter_map do |reply|
              next if reply['deletedDateTime'] || reply[:deletedDateTime]

              sender       = reply.dig('from', 'user', 'displayName') ||
                             reply.dig(:from, :user, :displayName) ||
                             'unknown'
              body_content = reply.dig('body', 'content') || reply.dig(:body, :content) || ''
              text         = body_content.gsub(/<[^>]+>/, '').strip
              next if text.empty?

              timestamp = reply['createdDateTime'] || reply[:createdDateTime]
              "  ↳ [#{timestamp}] #{sender}: #{text}"
            end
          rescue StandardError => e
            log.debug("fetch_reply_lines failed: #{e.message}")
            []
          end

          def ingest_members(chat_id, topic, results)
            report_progress(message: 'fetching members', percent: 80)
            response = chats_runner.list_chat_members(chat_id: chat_id, token: graph_token)
            body = response.is_a?(Hash) ? response[:result] : nil
            return unless body.is_a?(Hash)

            items = body['value'] || body[:value]
            return unless items.is_a?(Array) && items.any?

            names = items.filter_map do |m|
              m['displayName'] || m[:displayName]
            end
            return if names.empty?

            absorb_raw(
              content:      "Chat participants for '#{topic}': #{names.join(', ')}",
              tags:         ['teams', 'chat', 'participants', topic],
              content_type: 'teams_chat_participants',
              metadata:     { chat_id: chat_id, participant_count: names.length }
            )
            results[:chunks] += 1
          rescue StandardError => e
            log.warn("Member ingest failed: #{e.message}")
          end
        end
      end
    end
  end
end
