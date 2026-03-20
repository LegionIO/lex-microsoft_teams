# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module People
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def get_profile(user_id: 'me', **)
            response = graph_connection(**).get(user_path(user_id).to_s)
            { result: response.body }
          rescue StandardError => e
            { error: e.message }
          end

          def list_people(user_id: 'me', top: 25, **)
            params = { '$top' => top }
            response = graph_connection(**).get("#{user_path(user_id)}/people", params)
            { result: response.body }
          rescue StandardError => e
            { error: e.message }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
