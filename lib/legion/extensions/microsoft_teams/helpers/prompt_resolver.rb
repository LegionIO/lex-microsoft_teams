# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        module PromptResolver
          def resolve_prompt(mode:, conversation_id:, owner_id: nil, trace_context: nil)
            settings = teams_settings
            base = settings.dig(:bot, :system_prompt) || ''

            mode_prompt = settings.dig(:bot, mode, :system_prompt)
            prompt = mode_prompt || base

            overrides = conversation_overrides(conversation_id: conversation_id)
            prompt = "#{prompt}\n\n#{overrides[:system_prompt_append]}" if overrides && overrides[:system_prompt_append]

            pref_instructions = preference_instructions_for(owner_id: owner_id)
            prompt = "#{prompt}\n\n#{pref_instructions}" if pref_instructions

            prompt = "#{prompt}\n\n#{trace_context}" if trace_context && !trace_context.empty?

            prompt
          end

          def resolve_llm_config(conversation_id:, mode: nil, owner_id: nil) # rubocop:disable Lint/UnusedMethodArgument
            settings = teams_settings
            base_llm = settings.dig(:bot, :llm) || {}

            overrides = conversation_overrides(conversation_id: conversation_id)
            override_llm = overrides&.dig(:llm) || {}

            base_llm.merge(override_llm)
          end

          private

          def teams_settings
            if defined?(Legion::Settings) && Legion::Settings[:microsoft_teams]
              Legion::Settings[:microsoft_teams]
            else
              { bot: {} }
            end
          end

          def conversation_overrides(conversation_id: nil) # rubocop:disable Lint/UnusedMethodArgument
            nil
          end

          # H4: Remove after OP3 lands (advisory path serves Teams).
          # Teams calls Legion::LLM.chat directly (Bot#llm_respond) — it bypasses the legion-llm
          # executor and advisory pipeline entirely. Until OP3 wires Teams through the executor,
          # removing this local injection would silently drop preference context from bot responses.
          # Track: LegionIO/legion-gaia#40
          def preference_instructions_for(owner_id:)
            return nil unless owner_id
            return nil unless defined?(Legion::Extensions::Mesh::Helpers::PreferenceProfile)

            profile = Legion::Extensions::Mesh::Helpers::PreferenceProfile.resolve(owner_id: owner_id)
            Legion::Extensions::Mesh::Helpers::PreferenceProfile.preference_instructions(profile: profile)
          rescue StandardError => e
            if defined?(handle_exception)
              handle_exception(e, level: :warn, operation: 'PromptResolver#preference_instructions_for',
                               owner_id: owner_id)
            end
            nil
          end
        end
      end
    end
  end
end
