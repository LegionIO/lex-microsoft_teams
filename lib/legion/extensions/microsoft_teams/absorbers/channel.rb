# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Absorbers
        class Channel < Legion::Extensions::Absorbers::Base
          pattern :url, 'teams.microsoft.com/l/channel/*'
          pattern :url, 'teams.microsoft.com/l/message/*'
          description 'Absorbs a Teams channel thread (messages, replies, members) into Apollo'

          def absorb(url: nil, content: nil, metadata: {}, context: {}) # rubocop:disable Lint/UnusedMethodArgument
            log.debug("Channel#absorb url=#{url.inspect}")
            report_progress(message: 'extracting ids from url')
            ids = extract_ids(url)
            return { success: false, error: 'could not extract team/channel ids from url' } unless ids

            team_id    = ids[:team_id]
            channel_id = ids[:channel_id]
            message_id = ids[:message_id]

            report_progress(message: 'fetching channel metadata', percent: 10)
            channel = resolve_channel(team_id, channel_id)
            return { success: false, error: 'could not resolve channel' } unless channel

            channel_name = channel['displayName'] || channel[:displayName] || 'untitled channel'
            results = { team_id: team_id, channel_id: channel_id, channel_name: channel_name, chunks: 0 }

            if message_id
              # Scoped to a specific thread
              ingest_thread(team_id, channel_id, message_id, channel_name, results)
            else
              # Full channel ingest
              ingest_messages(team_id, channel_id, channel_name, results)
            end

            ingest_members(team_id, channel_id, channel_name, results)

            report_progress(message: 'done', percent: 100)
            log.info("Channel#absorb complete team_id=#{team_id} channel=#{channel_name} chunks=#{results[:chunks]}")
            results.merge(success: true)
          rescue StandardError => e
            handle_exception(e, level: :error, operation: 'Channel#absorb', url: url)
            { success: false, error: e.message }
          end

          private

          def channels_runner
            @channels_runner ||= Object.new.extend(Runners::Channels)
          end

          def channel_messages_runner
            @channel_messages_runner ||= Object.new.extend(Runners::ChannelMessages)
          end

          def graph_token
            Legion::Extensions::Identity::Entra::Helpers::TokenManager.load_token(:delegated)
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: 'Channel#graph_token')
            nil
          end

          # Teams channel URL formats:
          #   /l/channel/<encoded_channel_id>/<channel_name>?groupId=<team_id>&...
          #   /l/message/<encoded_channel_id>/<message_id>?groupId=<team_id>&...
          def extract_ids(url)
            log.debug("Channel#extract_ids url=#{url.inspect}")
            return nil unless url.is_a?(String)

            uri    = URI.parse(url)
            params = URI.decode_www_form(uri.query.to_s).to_h

            team_id    = params['groupId'] || params['groupid']
            return nil unless team_id

            path_parts = uri.path.split('/')
            # path: ["", "l", "channel"|"message", <encoded_id>, ...]
            encoded_id = path_parts[3]
            return nil unless encoded_id

            channel_id = URI.decode_uri_component(encoded_id)

            message_id = (path_parts[4] if uri.path.include?('/l/message/'))

            { team_id: team_id, channel_id: channel_id, message_id: message_id }
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: 'Channel#extract_ids', url: url)
            nil
          end

          def resolve_channel(team_id, channel_id)
            log.debug("Channel#resolve_channel team_id=#{team_id} channel_id=#{channel_id}")
            response = channels_runner.get_channel(team_id: team_id, channel_id: channel_id, token: graph_token)
            body = response.is_a?(Hash) ? response[:result] : nil
            return nil unless body.is_a?(Hash) && !body['error'] && !body[:error]

            body
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'Channel#resolve_channel',
                             team_id: team_id, channel_id: channel_id)
            nil
          end

          def ingest_messages(team_id, channel_id, channel_name, results)
            log.debug("Channel#ingest_messages team_id=#{team_id} channel_id=#{channel_id}")
            report_progress(message: 'fetching channel messages', percent: 25)
            response = channel_messages_runner.list_channel_messages(
              team_id: team_id, channel_id: channel_id, top: 50, token: graph_token
            )
            body  = response.is_a?(Hash) ? response[:result] : nil
            items = body.is_a?(Hash) ? (body['value'] || body[:value]) : nil
            return unless items.is_a?(Array) && items.any?

            items.reverse_each do |msg|
              ingest_single_message(team_id, channel_id, msg, channel_name, results)
            end
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'Channel#ingest_messages',
                             team_id: team_id, channel_id: channel_id)
          end

          def ingest_thread(team_id, channel_id, message_id, channel_name, results)
            log.debug("Channel#ingest_thread team_id=#{team_id} channel_id=#{channel_id} message_id=#{message_id}")
            report_progress(message: 'fetching thread root message', percent: 20)
            response = channel_messages_runner.get_channel_message(
              team_id: team_id, channel_id: channel_id, message_id: message_id, token: graph_token
            )
            body = response.is_a?(Hash) ? response[:result] : nil
            return unless body.is_a?(Hash) && !body['error']

            ingest_single_message(team_id, channel_id, body, channel_name, results, scoped_thread: true)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'Channel#ingest_thread',
                             team_id: team_id, channel_id: channel_id, message_id: message_id)
          end

          def ingest_single_message(team_id, channel_id, msg, channel_name, results, scoped_thread: false)
            return unless msg.is_a?(Hash)
            return if msg['deletedDateTime'] || msg[:deletedDateTime]
            return if (msg['messageType'] || msg[:messageType]) == 'unknownFutureValue'

            msg_id = msg['id'] || msg[:id]
            log.debug("Channel#ingest_single_message msg_id=#{msg_id} channel=#{channel_name}")
            sender       = msg.dig('from', 'user', 'displayName') ||
                           msg.dig(:from, :user, :displayName) ||
                           'unknown'
            body_content = msg.dig('body', 'content') || msg.dig(:body, :content) || ''
            text         = body_content.gsub(/<[^>]+>/, '').strip
            return if text.empty? && !scoped_thread

            subject   = msg['subject'] || msg[:subject]
            timestamp = msg['createdDateTime'] || msg[:createdDateTime]
            lines     = []
            lines << "Subject: #{subject}" if subject && !subject.empty?
            lines << "[#{timestamp}] #{sender}: #{text}" unless text.empty?

            reply_lines = fetch_reply_lines(team_id, channel_id, msg_id)
            lines.concat(reply_lines)

            return if lines.empty?

            percent = scoped_thread ? 60 : nil
            report_progress(message: "ingesting message #{msg_id}", percent: percent) if percent

            absorb_to_knowledge(
              content:      lines.join("\n"),
              tags:         ['teams', 'channel', 'thread', channel_name],
              source_file:  "teams://teams/#{team_id}/channels/#{channel_id}/messages/#{msg_id}",
              heading:      "Channel Thread: #{channel_name}#{" — #{subject}" if subject}",
              content_type: 'teams_channel_thread',
              access_scope: 'private'
            )
            results[:chunks] += 1
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'Channel#ingest_single_message',
                             msg_id: msg_id, channel: channel_name)
          end

          def fetch_reply_lines(team_id, channel_id, message_id)
            return [] unless message_id

            log.debug("Channel#fetch_reply_lines team_id=#{team_id} channel_id=#{channel_id} message_id=#{message_id}")
            response = channel_messages_runner.list_channel_message_replies(
              team_id: team_id, channel_id: channel_id, message_id: message_id, top: 50, token: graph_token
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
            handle_exception(e, level: :debug, operation: 'Channel#fetch_reply_lines',
                             team_id: team_id, channel_id: channel_id, message_id: message_id)
            []
          end

          def ingest_members(team_id, channel_id, channel_name, results)
            log.debug("Channel#ingest_members team_id=#{team_id} channel_id=#{channel_id}")
            report_progress(message: 'fetching channel members', percent: 85)
            response = channels_runner.list_channel_members(
              team_id: team_id, channel_id: channel_id, token: graph_token
            )
            body  = response.is_a?(Hash) ? response[:result] : nil
            items = body.is_a?(Hash) ? (body['value'] || body[:value]) : nil
            return unless items.is_a?(Array) && items.any?

            names = items.filter_map { |m| m['displayName'] || m[:displayName] }
            return if names.empty?

            absorb_raw(
              content:      "Channel members for '#{channel_name}': #{names.join(', ')}",
              tags:         ['teams', 'channel', 'members', channel_name],
              content_type: 'teams_channel_members',
              metadata:     { team_id: team_id, channel_id: channel_id, member_count: names.length }
            )
            results[:chunks] += 1
            log.info("Channel#ingest_members stored #{names.length} members for channel=#{channel_name}")
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'Channel#ingest_members',
                             team_id: team_id, channel_id: channel_id)
          end
        end
      end
    end
  end
end
