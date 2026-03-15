# frozen_string_literal: true

require 'legion/extensions/microsoft_teams/version'
require 'legion/extensions/microsoft_teams/helpers/client'
require 'legion/extensions/microsoft_teams/helpers/high_water_mark'
require 'legion/extensions/microsoft_teams/runners/auth'
require 'legion/extensions/microsoft_teams/runners/teams'
require 'legion/extensions/microsoft_teams/runners/chats'
require 'legion/extensions/microsoft_teams/runners/messages'
require 'legion/extensions/microsoft_teams/runners/channels'
require 'legion/extensions/microsoft_teams/runners/channel_messages'
require 'legion/extensions/microsoft_teams/runners/subscriptions'
require 'legion/extensions/microsoft_teams/runners/adaptive_cards'
require 'legion/extensions/microsoft_teams/runners/bot'
require 'legion/extensions/microsoft_teams/runners/local_cache'
require 'legion/extensions/microsoft_teams/runners/cache_ingest'
require 'legion/extensions/microsoft_teams/client'

module Legion
  module Extensions
    module MicrosoftTeams
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core
    end
  end
end
