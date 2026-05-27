# frozen_string_literal: true

require 'legion/extensions/identity/entra/helpers/token_manager'
require 'legion/extensions/microsoft_teams/version'
require 'legion/extensions/microsoft_teams/errors'
require 'legion/extensions/microsoft_teams/faraday/retry_after'
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
require 'legion/extensions/microsoft_teams/runners/ai_insights'
require 'legion/extensions/microsoft_teams/runners/local_cache'
require 'legion/extensions/microsoft_teams/runners/cache_ingest'
require 'legion/extensions/microsoft_teams/runners/people'
require 'legion/extensions/microsoft_teams/runners/profile_ingest'
require 'legion/extensions/microsoft_teams/runners/ownership'
require 'legion/extensions/microsoft_teams/runners/api_ingest'
require 'legion/extensions/microsoft_teams/runners/activities'
require 'legion/extensions/microsoft_teams/runners/meeting_artifacts'
require 'legion/extensions/microsoft_teams/runners/call_events'
require 'legion/extensions/microsoft_teams/runners/app_installations'
require 'legion/extensions/microsoft_teams/runners/files'

# Helpers (bot)
require 'legion/extensions/microsoft_teams/helpers/graph_cache'
require 'legion/extensions/microsoft_teams/helpers/high_water_mark'
require 'legion/extensions/microsoft_teams/helpers/prompt_resolver'
require 'legion/extensions/microsoft_teams/helpers/trace_retriever'
require 'legion/extensions/microsoft_teams/helpers/session_manager'
require 'legion/extensions/microsoft_teams/helpers/subscription_registry'
require 'legion/extensions/microsoft_teams/helpers/permission_guard'
require 'legion/extensions/microsoft_teams/helpers/transform_definitions'
require 'legion/extensions/microsoft_teams/helpers/graph_client'

# Transport
if Legion.const_defined?(:Transport, false)
  require 'legion/extensions/microsoft_teams/transport/exchanges/messages'
  require 'legion/extensions/microsoft_teams/transport/queues/messages_process'
  require 'legion/extensions/microsoft_teams/transport/messages/teams_message'
end

require 'legion/extensions/microsoft_teams/client'

if defined?(Legion::Extensions) &&
   Legion::Extensions.const_defined?(:Absorbers, false) &&
   Legion::Extensions::Absorbers.const_defined?(:Base, false)
  require_relative 'microsoft_teams/absorbers/meeting'
  require_relative 'microsoft_teams/absorbers/chat'
  require_relative 'microsoft_teams/absorbers/channel'
end

module Legion
  module Extensions
    module MicrosoftTeams
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core, false

      def self.default_settings # rubocop:disable Metrics/MethodLength
        {
          api_ingest:           {
            enabled:       true,
            interval:      3600,
            top_people:    15,
            message_depth: 50,
            skip_bots:     true
          },
          incremental_sync:     {
            enabled:       true,
            interval:      900,
            top_people:    10,
            message_depth: 50
          },
          profile_ingest:       {
            enabled:       true,
            top_people:    10,
            message_depth: 50
          },
          presence_poller:      {
            enabled:  false,
            interval: 300
          },
          meeting_ingest:       {
            enabled:  true,
            interval: 900
          },
          channel_poller:       {
            enabled:               false,
            interval:              120,
            max_teams:             10,
            max_channels_per_team: 5
          },
          direct_chat_poller:   {
            enabled:  false,
            interval: 30
          },
          observed_chat_poller: {
            enabled:  false,
            interval: 60
          },
          cache:                {
            graph_ttl: 300
          },
          client:               {
            throttle_circuit: {
              soft_percentage: 0.8,
              soft_ttl:        60,
              fallback_ttl:    60,
              insights_ttl:    600
            }
          }
        }
      end

      def self.trigger_words
        %w[teams microsoft_teams microsoftteams microsoft-teams msteams ms-teams]
      end

      def self.remote_invocable?
        false
      end
    end
  end
end
