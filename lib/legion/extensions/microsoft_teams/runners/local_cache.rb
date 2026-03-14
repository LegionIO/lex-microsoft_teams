# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/local_cache/extractor'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module LocalCache
          # Extract messages from the local Teams LevelDB cache.
          # Works offline without Graph API credentials.
          def extract_local_messages(db_path: nil, since: nil, channels: nil, senders: nil, skip_bots: true, **)
            opts = {}
            opts[:db_path] = db_path if db_path
            extractor = MicrosoftTeams::LocalCache::Extractor.new(**opts)
            messages = extractor.extract(since: since, channels: channels,
                                         senders: senders, skip_bots: skip_bots)
            { result: messages.map { |m| message_to_hash(m) } }
          end

          # Check if the local Teams cache is available.
          def local_cache_available?(db_path: nil, **)
            opts = {}
            opts[:db_path] = db_path if db_path
            extractor = MicrosoftTeams::LocalCache::Extractor.new(**opts)
            { result: extractor.available? }
          end

          # Get stats about the local Teams cache without extracting messages.
          def local_cache_stats(db_path: nil, **)
            opts = {}
            opts[:db_path] = db_path if db_path
            extractor = MicrosoftTeams::LocalCache::Extractor.new(**opts)
            { result: extractor.stats }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)

          private

          def message_to_hash(msg)
            {
              content:       msg.content,
              sender:        msg.sender,
              sender_id:     msg.sender_id,
              message_type:  msg.message_type,
              content_type:  msg.content_type,
              compose_time:  msg.compose_time,
              thread_id:     msg.thread_id,
              thread_type:   msg.thread_type,
              thread_topic:  msg.thread_topic,
              client_msg_id: msg.client_msg_id,
              content_hash:  msg.content_hash,
              message_id:    msg.message_id
            }
          end
        end
      end
    end
  end
end
