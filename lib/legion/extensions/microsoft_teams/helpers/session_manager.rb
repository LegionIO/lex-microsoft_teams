# frozen_string_literal: true

require_relative 'prompt_resolver'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        class SessionManager
          include PromptResolver
          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)

          DEFAULT_FLUSH_THRESHOLD = 20
          DEFAULT_IDLE_TIMEOUT = 900
          DEFAULT_MAX_RECENT = 5

          def initialize(flush_threshold: nil, idle_timeout: nil, max_recent: nil)
            @sessions = {}
            @flush_threshold = flush_threshold || settings_val(:flush_threshold, DEFAULT_FLUSH_THRESHOLD)
            @idle_timeout = idle_timeout || settings_val(:idle_timeout, DEFAULT_IDLE_TIMEOUT)
            @max_recent = max_recent || settings_val(:max_recent_messages, DEFAULT_MAX_RECENT)
          end

          def get_or_create(conversation_id:, owner_id:, mode:)
            return @sessions[conversation_id] if @sessions.key?(conversation_id)

            session = {
              owner_id:      owner_id,
              mode:          mode,
              message_count: 0,
              last_active:   Time.now,
              messages:      [],
              system_prompt: resolve_prompt(mode: mode, conversation_id: conversation_id, owner_id: owner_id),
              llm_config:    resolve_llm_config(mode: mode, conversation_id: conversation_id, owner_id: owner_id)
            }

            @sessions[conversation_id] = session
          end

          def refresh_prompt(conversation_id:)
            return nil unless @sessions.key?(conversation_id)

            session = @sessions[conversation_id]
            session[:system_prompt] = resolve_prompt(
              mode: session[:mode], conversation_id: conversation_id, owner_id: session[:owner_id]
            )
            session[:system_prompt]
          end

          def touch(conversation_id:)
            return unless @sessions.key?(conversation_id)

            @sessions[conversation_id][:message_count] += 1
            @sessions[conversation_id][:last_active] = Time.now
          end

          def add_message(conversation_id:, role:, content:)
            return unless @sessions.key?(conversation_id)

            @sessions[conversation_id][:messages] << { role: role, content: content, at: Time.now }
          end

          def recent_messages(conversation_id:, count: nil)
            return [] unless @sessions.key?(conversation_id)

            msgs = @sessions[conversation_id][:messages]
            msgs.last(count || @max_recent)
          end

          def should_flush?(conversation_id:)
            return false unless @sessions.key?(conversation_id)

            @sessions[conversation_id][:message_count] >= @flush_threshold
          end

          def persist(conversation_id:)
            return unless @sessions.key?(conversation_id)

            session = @sessions[conversation_id]
            store_session_to_memory(conversation_id: conversation_id, session: session)
            session[:message_count] = 0
          end

          def flush_idle(timeout: nil)
            timeout ||= @idle_timeout
            cutoff = Time.now - timeout
            flushed = []

            @sessions.each do |conv_id, session|
              next unless session[:last_active] < cutoff

              persist(conversation_id: conv_id)
              flushed << conv_id
            end

            flushed.each { |conv_id| @sessions.delete(conv_id) }
            flushed
          end

          def shutdown
            @sessions.each_key { |conv_id| persist(conversation_id: conv_id) }
            @sessions.clear
          end

          def active_sessions
            @sessions.size
          end

          private

          def store_session_to_memory(conversation_id:, session:)
            return unless defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)

            memory_runner.store_trace(
              type:            :episodic,
              content_payload: {
                type:            :bot_session,
                conversation_id: conversation_id,
                owner_id:        session[:owner_id],
                recent_messages: session[:messages].last(@max_recent),
                message_count:   session[:message_count],
                last_active:     session[:last_active].iso8601
              }.to_s,
              domain_tags:     ['teams', 'bot-session', "conv:#{conversation_id}"],
              origin:          :direct_experience,
              confidence:      0.8
            )
          rescue StandardError => e
            log.error("SessionManager persist failed: #{e.message}")
          end

          def memory_runner
            @memory_runner ||= Object.new.extend(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def settings_val(key, default)
            if defined?(Legion::Settings) && Legion::Settings.dig(:microsoft_teams, :bot, :session, key)
              Legion::Settings[:microsoft_teams][:bot][:session][key]
            else
              default
            end
          end
        end
      end
    end
  end
end
