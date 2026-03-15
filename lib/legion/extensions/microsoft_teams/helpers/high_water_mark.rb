# frozen_string_literal: true

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
              Legion::Cache.get(key)
            else
              @hwm_fallback ||= {}
              @hwm_fallback[key]
            end
          end

          def set_hwm(chat_id:, timestamp:)
            key = hwm_key(chat_id: chat_id)
            if cache_available?
              Legion::Cache.set(key, timestamp, HWM_TTL)
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
