# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module People
          extend Legion::Extensions::Definitions
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def self.trigger_words
            %w[profile people person colleague colleagues contact contacts]
          end

          definition :get_profile,
                     desc:          'Get the Microsoft Graph profile for a user',
                     mcp_prefix:    'teams.get_profile',
                     mcp_category:  'teams_people',
                     mcp_tier:      :low,
                     idempotent:    true,
                     trigger_words: %w[profile self]

          def get_profile(user_id: 'me', **)
            log.debug("People#get_profile user_id=#{user_id}")
            response = graph_connection(**).get(user_path(user_id).to_s)
            { result: response.body }
          rescue StandardError => e
            handle_exception(e, level: :error, operation: 'People#get_profile', user_id: user_id)
            { error: e.message }
          end

          definition :list_people,
                     desc:          'List people relevant to the current user with search and filter support',
                     mcp_prefix:    'teams.list_people',
                     mcp_category:  'teams_people',
                     mcp_tier:      :standard,
                     idempotent:    true,
                     inputs:        { properties: { top:    { type:        'integer',
                                                              description: 'Number of people to return (default 25)' },
                                                    search: { type:        'string',
                                                              description: 'Search term to find people by name or email' },
                                                    filter: { type:        'string',
                                                              description: 'OData $filter expression' },
                                                    select: { type:        'string',
                                                              description: 'Comma-separated fields to return' } },
                                      required:   [] },
                     trigger_words: %w[people colleagues contacts]

          def list_people(user_id: 'me', top: 25, search: nil, filter: nil, select: nil, **)
            log.debug("People#list_people user_id=#{user_id} top=#{top}")
            params = { '$top' => top }
            params['$search'] = "\"#{search}\"" if search
            params['$filter'] = filter if filter
            params['$select'] = select if select
            response = graph_connection(**).get("#{user_path(user_id)}/people", params)
            { result: response.body }
          rescue StandardError => e
            handle_exception(e, level: :error, operation: 'People#list_people', user_id: user_id)
            { error: e.message }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
