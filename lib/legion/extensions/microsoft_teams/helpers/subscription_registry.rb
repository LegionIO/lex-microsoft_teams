# frozen_string_literal: true

require 'json'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        class SubscriptionRegistry
          MEMORY_KEY = 'teams_bot_subscriptions'

          def initialize
            @subscriptions = {}
            @mutex = Mutex.new
            load
          end

          def subscribe(owner_id:, chat_id:, peer_name:)
            @mutex.synchronize do
              return if @subscriptions.key?(chat_id)

              @subscriptions[chat_id] = {
                owner_id:   owner_id,
                peer_name:  peer_name,
                enabled:    true,
                notify:     true,
                created_at: Time.now
              }
            end
            persist
          end

          def unsubscribe(owner_id:, chat_id:) # rubocop:disable Lint/UnusedMethodArgument
            @mutex.synchronize { @subscriptions.delete(chat_id) }
            persist
          end

          def list(owner_id:)
            @mutex.synchronize do
              @subscriptions.select { |_, v| v[:owner_id] == owner_id }
                            .map { |chat_id, v| v.merge(chat_id: chat_id) }
            end
          end

          def pause(owner_id:, chat_id:) # rubocop:disable Lint/UnusedMethodArgument
            @mutex.synchronize do
              @subscriptions[chat_id][:enabled] = false if @subscriptions.key?(chat_id)
            end
            persist
          end

          def resume(owner_id:, chat_id:) # rubocop:disable Lint/UnusedMethodArgument
            @mutex.synchronize do
              @subscriptions[chat_id][:enabled] = true if @subscriptions.key?(chat_id)
            end
            persist
          end

          def active_subscriptions
            @mutex.synchronize do
              @subscriptions.select { |_, v| v[:enabled] }
                            .map { |chat_id, v| v.merge(chat_id: chat_id) }
            end
          end

          def find_by_peer_name(owner_id:, peer_name:)
            @mutex.synchronize do
              @subscriptions.each do |chat_id, v|
                next unless v[:owner_id] == owner_id
                next unless v[:peer_name].downcase == peer_name.downcase

                return v.merge(chat_id: chat_id)
              end
              nil
            end
          end

          def load
            return unless memory_available?

            result = memory_runner.retrieve_by_domain(domain_tag: MEMORY_KEY, limit: 1)
            stored = result&.dig(:traces)&.first
            return unless stored&.dig(:content_payload)

            parsed = parse_stored(stored[:content_payload])
            @mutex.synchronize { @subscriptions = parsed } if parsed.is_a?(Hash)
          rescue StandardError => e
            log_error("SubscriptionRegistry load failed: #{e.message}")
          end

          def persist
            return unless memory_available?

            memory_runner.store_trace(
              type:            :semantic,
              content_payload: serialize_subscriptions,
              domain_tags:     [MEMORY_KEY],
              origin:          :system,
              confidence:      1.0
            )
          rescue StandardError => e
            log_error("SubscriptionRegistry persist failed: #{e.message}")
          end

          private

          def serialize_subscriptions
            serializable = @subscriptions.transform_values do |v|
              v.merge(created_at: v[:created_at]&.iso8601)
            end
            ::JSON.generate(serializable)
          end

          def parse_stored(payload)
            return payload if payload.is_a?(Hash)
            return {} unless payload.is_a?(String)

            parsed = ::JSON.parse(payload, symbolize_names: true)
            parsed.transform_values do |v|
              v[:created_at] = Time.parse(v[:created_at]) if v[:created_at].is_a?(String)
              v
            end
          rescue ::JSON::ParserError
            {}
          end

          def memory_available?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def memory_runner
            @memory_runner ||= Object.new.extend(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def log_error(msg)
            Legion::Logging.error(msg) if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
