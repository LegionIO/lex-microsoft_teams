# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Auth
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          def acquire_token(tenant_id:, client_id:, client_secret:, scope: 'https://graph.microsoft.com/.default', **)
            response = oauth_connection(tenant_id: tenant_id).post('/oauth2/v2.0/token', {
                                                                     grant_type:    'client_credentials',
                                                                     client_id:     client_id,
                                                                     client_secret: client_secret,
                                                                     scope:         scope
                                                                   })
            { result: response.body }
          end

          def acquire_bot_token(client_id:, client_secret:,
                                scope: 'https://api.botframework.com/.default', **)
            response = oauth_connection(tenant_id: 'botframework.com').post('/oauth2/v2.0/token', {
                                                                             grant_type:    'client_credentials',
                                                                             client_id:     client_id,
                                                                             client_secret: client_secret,
                                                                             scope:         scope
                                                                           })
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
