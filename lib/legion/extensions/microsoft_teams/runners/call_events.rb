# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module CallEvents
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[call calls session sessions segment pstn]
          end

          definition :list_call_sessions,
                     desc:          'List sessions for a Teams call record',
                     mcp_prefix:    'teams.list_call_sessions',
                     mcp_category:  'teams_calls',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { call_id: { type: 'string' } }, required: ['call_id'] },
                     trigger_words: %w[sessions calls records]

          def list_call_sessions(call_id:, **)
            response = graph_connection(**).get("communications/callRecords/#{call_id}/sessions")
            { result: response.body }
          end

          definition :get_call_session,
                     desc:          'Get a specific session from a Teams call record',
                     mcp_prefix:    'teams.get_call_session',
                     mcp_category:  'teams_calls',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { call_id:    { type: 'string' },
                                                    session_id: { type: 'string' } },
                                      required:   %w[call_id session_id] },
                     trigger_words: %w[session call record]

          def get_call_session(call_id:, session_id:, **)
            response = graph_connection(**).get(
              "communications/callRecords/#{call_id}/sessions/#{session_id}"
            )
            { result: response.body }
          end

          definition :list_session_segments,
                     desc:          'List segments for a session in a Teams call record',
                     mcp_prefix:    'teams.list_session_segments',
                     mcp_category:  'teams_calls',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { call_id:    { type: 'string' },
                                                    session_id: { type: 'string' } },
                                      required:   %w[call_id session_id] },
                     trigger_words: %w[segments pstn]

          def list_session_segments(call_id:, session_id:, **)
            response = graph_connection(**).get(
              "communications/callRecords/#{call_id}/sessions/#{session_id}/segments"
            )
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
