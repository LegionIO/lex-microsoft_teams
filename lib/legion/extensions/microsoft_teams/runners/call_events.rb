# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module CallEvents
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def list_call_sessions(call_id:, **)
            response = graph_connection(**).get("communications/callRecords/#{call_id}/sessions")
            { result: response.body }
          end

          def get_call_session(call_id:, session_id:, **)
            response = graph_connection(**).get(
              "communications/callRecords/#{call_id}/sessions/#{session_id}"
            )
            { result: response.body }
          end

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
