# frozen_string_literal: true

require 'json'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        module HighWaterMark
          HWM_TTL = 86_400 # 24 hours

          def hwm_key(chat_id:)
            "teams:hwm:#{chat_id}"
          end

          def get_hwm(chat_id:)
            key = hwm_key(chat_id: chat_id)
            if cache_available?
              cache_get(key)
            else
              @hwm_fallback ||= {}
              @hwm_fallback[key]
            end
          end

          def set_hwm(chat_id:, timestamp:)
            key = hwm_key(chat_id: chat_id)
            if cache_available?
              cache_set(key, timestamp, HWM_TTL)
            else
              @hwm_fallback ||= {}
              @hwm_fallback[key] = timestamp
            end
          end

          def new_messages(chat_id:, messages:)
            hwm = get_hwm(chat_id: chat_id)
            return messages if hwm.nil?

            messages.select { |m| m[:createdDateTime] > hwm }
          end

          def update_hwm_from_messages(chat_id:, messages:)
            return if messages.empty?

            latest = messages.map { |m| m[:createdDateTime] }.max
            set_hwm(chat_id: chat_id, timestamp: latest)
          end

          def get_extended_hwm(chat_id:)
            key = "teams:ehwm:#{chat_id}"
            raw = if cache_available?
                    cache_get(key)
                  else
                    @ehwm_fallback ||= {}
                    @ehwm_fallback[key]
                  end
            return nil unless raw

            raw.is_a?(Hash) ? raw : ::JSON.parse(raw, symbolize_names: true)
          rescue StandardError => e
            log.debug("HighWaterMark: get_extended_hwm failed to parse cached value: #{e.message}")
            nil
          end

          def set_extended_hwm(chat_id:, last_message_at:, last_ingested_at:, message_count: 0)
            key = "teams:ehwm:#{chat_id}"
            value = { last_message_at: last_message_at, last_ingested_at: last_ingested_at,
                      message_count: message_count }
            if cache_available?
              cache_set(key, ::JSON.dump(value), HWM_TTL)
            else
              @ehwm_fallback ||= {}
              @ehwm_fallback[key] = value
            end
          end

          def update_extended_hwm(chat_id:, last_message_at:, new_message_count: 0, ingested: false)
            existing = get_extended_hwm(chat_id: chat_id) || { last_message_at: nil, last_ingested_at: nil, message_count: 0 }
            existing[:last_message_at] = last_message_at
            existing[:message_count] = (existing[:message_count] || 0) + new_message_count
            existing[:last_ingested_at] = Time.now.utc.iso8601 if ingested
            set_extended_hwm(chat_id: chat_id, **existing)
          end

          def persist_hwm_as_trace(chat_id:)
            hwm = get_extended_hwm(chat_id: chat_id)
            return unless hwm

            memory_runner.store_trace(
              type:            :procedural,
              content_payload: ::JSON.dump({ chat_id: chat_id }.merge(hwm)),
              domain_tags:     ['teams', 'hwm', "chat:#{chat_id}"],
              confidence:      1.0,
              origin:          :direct_experience
            )
          end

          def restore_hwm_from_traces
            traces = memory_runner.retrieve_by_domain(domain_tag: 'teams', min_strength: 0.0, limit: 500)
            return unless traces.is_a?(Array)

            traces.select { |t| t[:trace_type] == :procedural && t[:domain_tags]&.include?('hwm') }.each do |trace|
              data = ::JSON.parse(trace[:content_payload], symbolize_names: true)
              next unless data[:chat_id]

              set_extended_hwm(chat_id: data[:chat_id], last_message_at: data[:last_message_at],
                               last_ingested_at: data[:last_ingested_at], message_count: data[:message_count] || 0)
            end
          rescue StandardError => e
            log.warn("Failed to restore HWM from traces: #{e.message}") if respond_to?(:log_warn, true)
          end

          def memory_runner
            @memory_runner ||= begin
              runner = Object.new
              runner.extend(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
              runner
            end
          end

          private

          def cache_available?
            defined?(Legion::Cache) &&
              Legion::Cache.respond_to?(:connected?) &&
              Legion::Cache.connected?
          end
        end
      end
    end
  end
end
