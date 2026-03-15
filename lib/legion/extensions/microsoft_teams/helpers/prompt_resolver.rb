# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        module PromptResolver
          def resolve_prompt(mode:, conversation_id:)
            settings = teams_settings
            base = settings.dig(:bot, :system_prompt) || ''

            mode_prompt = settings.dig(:bot, mode, :system_prompt)
            prompt = mode_prompt || base

            overrides = conversation_overrides(conversation_id: conversation_id)
            prompt = "#{prompt}\n\n#{overrides[:system_prompt_append]}" if overrides && overrides[:system_prompt_append]

            prompt
          end

          def resolve_llm_config(conversation_id:, mode: nil) # rubocop:disable Lint/UnusedMethodArgument
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

          def conversation_overrides(conversation_id: nil)
            return nil unless conversation_id
            return nil unless defined?(Legion::Extensions::Memory::Runners::Traces)

            nil # TODO: query lex-memory for conversation_config by conversation_id
          end
        end
      end
    end
  end
end
