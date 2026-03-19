# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/helpers/client'
require 'legion/extensions/microsoft_teams/runners/auth'
require 'legion/extensions/microsoft_teams/runners/teams'
require 'legion/extensions/microsoft_teams/runners/chats'
require 'legion/extensions/microsoft_teams/runners/messages'
require 'legion/extensions/microsoft_teams/runners/channels'
require 'legion/extensions/microsoft_teams/runners/channel_messages'
require 'legion/extensions/microsoft_teams/runners/subscriptions'
require 'legion/extensions/microsoft_teams/runners/adaptive_cards'
require 'legion/extensions/microsoft_teams/runners/bot'
require 'legion/extensions/microsoft_teams/runners/presence'
require 'legion/extensions/microsoft_teams/runners/meetings'
require 'legion/extensions/microsoft_teams/runners/transcripts'

module Legion
  module Extensions
    module MicrosoftTeams
      class Client
        include Helpers::Client
        include Runners::Auth
        include Runners::Teams
        include Runners::Chats
        include Runners::Messages
        include Runners::Channels
        include Runners::ChannelMessages
        include Runners::Subscriptions
        include Runners::AdaptiveCards
        include Runners::Bot
        include Runners::Presence
        include Runners::Meetings
        include Runners::Transcripts
        include Runners::LocalCache
        include Runners::CacheIngest

        attr_reader :opts

        def initialize(tenant_id: nil, client_id: nil, client_secret: nil, token: nil,
                       user_id: 'me', **extra)
          @opts = { tenant_id: tenant_id, client_id: client_id, client_secret: client_secret,
                    token: token, user_id: user_id, **extra }
        end

        def graph_connection(**override)
          super(**@opts.merge(override))
        end

        def bot_connection(**override)
          super(**@opts.merge(override))
        end

        def oauth_connection(**override)
          super(**@opts.merge(override))
        end

        def authenticate!
          result = acquire_token(
            tenant_id:     @opts[:tenant_id],
            client_id:     @opts[:client_id],
            client_secret: @opts[:client_secret]
          )
          return result unless result&.dig(:result, 'access_token')

          @opts[:token] = result[:result]['access_token']
          result
        end
      end
    end
  end
end
