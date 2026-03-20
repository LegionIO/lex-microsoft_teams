# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        module TransformDefinitions
          module_function

          def conversation_extract
            {
              name: 'teams.conversation.extract',
              structured: true,
              prompt: 'Analyze this conversation between two people. Extract their communication ' \
                      'style, recurring topics, the nature of their working relationship, and any ' \
                      'pending action items. Be concise.',
              schema: {
                type: :object,
                properties: {
                  communication_style: { type: :string, description: 'How this person communicates (formal, casual, terse, detailed, etc.)' },
                  topics: { type: :array, items: { type: :string }, description: 'Recurring discussion topics' },
                  relationship_context: { type: :string, description: 'Nature of working relationship (manager, peer, cross-team, mentor, etc.)' },
                  action_items: { type: :array, items: { type: :string }, description: 'Pending tasks or follow-ups' }
                },
                required: %i[communication_style topics relationship_context action_items]
              },
              engine_options: { max_retries: 2 }
            }
          end

          def person_summary
            {
              name: 'teams.person.summary',
              structured: true,
              prompt: 'Given this person profile data from Microsoft Teams, write a brief summary ' \
                      'of who this person is and their role. Keep it factual and concise.',
              schema: {
                type: :object,
                properties: {
                  summary: { type: :string, description: 'One-sentence summary of this person' },
                  role_category: { type: :string, description: 'Role category: engineering, management, design, product, support, other' }
                },
                required: %i[summary role_category]
              },
              engine_options: { max_retries: 1 }
            }
          end
        end
      end
    end
  end
end
