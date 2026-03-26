# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/local_cache/extractor'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module CacheIngest
          # Ingest Teams messages from local cache into lex-memory traces.
          # Returns count of new traces stored and the latest compose_time seen.
          def ingest_cache(since: nil, skip_bots: true, db_path: nil, imprint_active: false, **)
            return { result: { stored: 0, skipped: 0, latest_time: nil, error: 'lex-memory not loaded' } } unless memory_available?

            opts = {}
            opts[:db_path] = db_path if db_path
            extractor = MicrosoftTeams::LocalCache::Extractor.new(**opts)

            return { result: { stored: 0, skipped: 0, latest_time: nil, error: 'Teams cache not found' } } unless extractor.available?

            since_time = since.is_a?(String) ? Time.parse(since) : since
            messages = extractor.extract(since: since_time, skip_bots: skip_bots)

            stored = 0
            skipped = 0
            latest_time = nil
            thread_groups = Hash.new { |h, k| h[k] = [] }

            messages.each do |msg|
              text = strip_html(msg.content)
              next if text.empty? || text.length < 5

              trace_result = store_message_trace(msg, text, imprint_active: imprint_active)
              if trace_result
                stored += 1
                thread_groups[msg.thread_id] << trace_result[:trace_id] if msg.thread_id
              else
                skipped += 1
              end

              latest_time = msg.compose_time if msg.compose_time && (latest_time.nil? || msg.compose_time > latest_time)
            end

            coactivate_thread_traces(thread_groups)
            flush_trace_store if stored.positive?

            { result: { stored: stored, skipped: skipped, latest_time: latest_time } }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)

          private

          def strip_html(html)
            return '' if html.nil? || html.empty?

            html.gsub(/<[^>]+>/, ' ').gsub('&nbsp;', ' ').gsub('&amp;', '&')
                .gsub('&lt;', '<').gsub('&gt;', '>').gsub('&quot;', '"')
                .gsub(/\s+/, ' ').strip
          end

          def memory_available?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def memory_runner
            @memory_runner ||= Object.new.extend(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def store_message_trace(msg, text, imprint_active: false)
            domain_tags = build_domain_tags(msg)

            memory_runner.store_trace(
              type:                :episodic,
              content_payload:     text,
              domain_tags:         domain_tags,
              origin:              :direct_experience,
              confidence:          0.6,
              emotional_valence:   0.1,
              emotional_intensity: 0.2,
              imprint_active:      imprint_active
            )
          rescue StandardError => e
            log.warn("CacheIngest: failed to store trace: #{e.message}")
            nil
          end

          def build_domain_tags(msg)
            tags = ['teams']
            if msg.sender
              tags << "sender:#{msg.sender}"
              tags << "peer:#{msg.sender}"
            end
            tags << "thread:#{msg.thread_topic}" if msg.thread_topic
            tags << "thread_id:#{msg.thread_id}" if msg.thread_id
            tags << "thread_type:#{msg.thread_type}" if msg.thread_type
            tags << "hash:#{msg.content_hash}" if msg.content_hash
            tags << "time:#{msg.compose_time}" if msg.compose_time
            tags << "msg_type:#{msg.message_type}" if msg.message_type
            tags
          end

          def flush_trace_store
            store = Legion::Extensions::Agentic::Memory::Trace.shared_store
            store.flush if store.respond_to?(:flush)
          rescue StandardError => e
            log.warn("CacheIngest: flush failed: #{e.message}")
          end

          # Seed Hebbian coactivation links between messages in the same thread.
          def coactivate_thread_traces(thread_groups)
            return unless defined?(Legion::Extensions::Agentic::Memory::Trace::Helpers::Store)

            store = Legion::Extensions::Agentic::Memory::Trace.shared_store
            thread_groups.each_value do |trace_ids|
              next if trace_ids.length < 2

              trace_ids.each_cons(2) do |id_a, id_b|
                store.record_coactivation(id_a, id_b)
              rescue StandardError => e
                log.debug("CacheIngest: coactivation link failed for #{id_a}/#{id_b}: #{e.message}")
                nil
              end
            end
          rescue StandardError => e
            log.debug("CacheIngest: coactivation linking skipped: #{e.message}")
          end
        end
      end
    end
  end
end
