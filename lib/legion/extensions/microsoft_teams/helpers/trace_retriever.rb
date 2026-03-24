# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        module TraceRetriever
          MAX_TRACE_TOKENS = 2000
          MAX_TRACES = 20

          def retrieve_context(message:, owner_id:, chat_id: nil, channel_id: nil) # rubocop:disable Lint/UnusedMethodArgument
            return nil unless memory_trace_available?

            traces = []
            traces.concat(retrieve_sender_traces(owner_id: owner_id))
            traces.concat(retrieve_teams_traces)
            traces.concat(retrieve_chat_traces(chat_id: chat_id)) if chat_id

            ranked = rank_traces(traces: traces, query: message)
            format_trace_context(traces: ranked.first(MAX_TRACES))
          rescue StandardError => e
            log_trace_error('retrieve_context', e)
            nil
          end

          private

          def retrieve_sender_traces(owner_id:)
            return [] unless owner_id

            store = shared_trace_store
            return [] unless store

            store.retrieve_by_domain("sender:#{owner_id}", min_strength: 0.1, limit: 10)
          rescue StandardError => e
            log_trace_error('retrieve_sender_traces', e)
            []
          end

          def retrieve_teams_traces
            store = shared_trace_store
            return [] unless store

            store.retrieve_by_domain('teams', min_strength: 0.3, limit: 10)
          rescue StandardError => e
            log_trace_error('retrieve_teams_traces', e)
            []
          end

          def retrieve_chat_traces(chat_id:)
            store = shared_trace_store
            return [] unless store

            store.retrieve_by_domain("chat:#{chat_id}", min_strength: 0.1, limit: 5)
          rescue StandardError => e
            log_trace_error('retrieve_chat_traces', e)
            []
          end

          def rank_traces(traces:, query:) # rubocop:disable Lint/UnusedMethodArgument
            seen = Set.new
            unique = traces.select { |t| seen.add?(t[:trace_id]) }

            unique.sort_by { |t| [-(t[:strength] || 0.0), -t[:last_reinforced].to_f] }
          end

          def format_trace_context(traces:)
            return nil if traces.empty?

            lines = ['## Organizational Context (from memory)']
            token_estimate = 0

            traces.each do |trace|
              line = format_single_trace(trace)
              next unless line

              line_tokens = line.length / 4
              break if token_estimate + line_tokens > MAX_TRACE_TOKENS

              lines << line
              token_estimate += line_tokens
            end

            return nil if lines.size <= 1

            lines.join("\n")
          end

          def format_single_trace(trace)
            type = trace[:trace_type] || :unknown
            content = trace[:content_payload].to_s
            content = "#{content[0, 200]}..." if content.length > 200

            tags = (trace[:domain_tags] || []).join(', ')
            age = trace_age_label(trace[:created_at] || trace[:last_reinforced])

            "- [#{type}] #{content} (#{age}, tags: #{tags})"
          rescue StandardError
            nil
          end

          def trace_age_label(timestamp)
            return 'unknown age' unless timestamp

            seconds = Time.now - (timestamp.is_a?(Time) ? timestamp : Time.parse(timestamp.to_s))
            case seconds
            when 0..3600 then 'just now'
            when 3600..86_400 then "#{(seconds / 3600).to_i}h ago"
            when 86_400..604_800 then "#{(seconds / 86_400).to_i}d ago"
            else "#{(seconds / 604_800).to_i}w ago"
            end
          rescue StandardError
            'unknown age'
          end

          def memory_trace_available?
            defined?(Legion::Extensions::Agentic::Memory::Trace)
          end

          def shared_trace_store
            return nil unless defined?(Legion::Extensions::Agentic::Memory::Trace) &&
                              Legion::Extensions::Agentic::Memory::Trace.respond_to?(:shared_store)

            Legion::Extensions::Agentic::Memory::Trace.shared_store
          end

          def log_trace_error(method, error)
            return unless defined?(log)

            log.debug("TraceRetriever##{method} failed: #{error.message}")
          end
        end
      end
    end
  end
end
