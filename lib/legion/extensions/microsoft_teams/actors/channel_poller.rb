# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class ChannelPoller < Legion::Extensions::Actors::Every
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          DEFAULT_INTERVAL       = 60
          DEFAULT_MAX_TEAMS      = 10
          DEFAULT_MAX_CHANNELS   = 5

          def initialize(**opts)
            return unless enabled?

            @channel_hwm = {}
            super
          end

          def runner_class    = self.class
          def runner_function = 'manual'
          def time            = channel_setting(:poll_interval, DEFAULT_INTERVAL)
          def run_now?        = false
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def memory_available?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def memory_runner
            @memory_runner ||= Object.new.extend(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def enabled?
            return false unless defined?(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache)

            channel_setting(:enabled, false) == true
          rescue StandardError
            false
          end

          def token_cache
            Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.instance
          end

          def manual
            log_info('ChannelPoller polling team channels')
            token = token_cache.cached_graph_token
            unless token
              log_debug('No token available, skipping poll')
              return
            end

            teams = fetch_joined_teams(token: token)
            log_debug("Found #{teams.length} joined team(s)")

            teams.first(max_teams).each do |team|
              poll_team(team: team, token: token)
            rescue StandardError => e
              log_error("Error polling team #{team['displayName']}: #{e.message}")
            end
          rescue StandardError => e
            log_error("ChannelPoller: #{e.message}")
          end

          private

          def fetch_joined_teams(token:)
            conn = graph_connection(token: token)
            response = conn.get('me/joinedTeams')
            response.body&.dig('value') || []
          rescue StandardError => e
            log_error("Failed to fetch joined teams: #{e.message}")
            []
          end

          def poll_team(team:, token:)
            team_id   = team['id']
            team_name = team['displayName'] || team_id

            channels = fetch_channels(team_id: team_id, token: token)
            selected = select_channels(channels)

            selected.first(max_channels_per_team).each do |channel|
              poll_channel(team_id: team_id, team_name: team_name, channel: channel, token: token)
            rescue StandardError => e
              log_error("Error polling channel #{channel['displayName']} in #{team_name}: #{e.message}")
            end
          end

          def fetch_channels(team_id:, token:)
            conn = graph_connection(token: token)
            response = conn.get("teams/#{team_id}/channels")
            response.body&.dig('value') || []
          rescue StandardError => e
            log_error("Failed to fetch channels for team #{team_id}: #{e.message}")
            []
          end

          def select_channels(channels)
            return channels if channel_setting(:all_channels, false) == true

            general = channels.select { |c| c['displayName'] == 'General' }
            general.any? ? general : channels
          end

          def poll_channel(team_id:, team_name:, channel:, token:)
            channel_id   = channel['id']
            channel_name = channel['displayName'] || channel_id

            conn     = graph_connection(token: token)
            response = conn.get(
              "teams/#{team_id}/channels/#{channel_id}/messages",
              { '$top' => 10, '$orderby' => 'lastModifiedDateTime desc' }
            )
            messages = response.body&.dig('value') || []

            new_msgs = filter_new_messages(channel_id: channel_id, messages: messages)
            return if new_msgs.empty?

            log_info("#{team_name} / #{channel_name}: #{new_msgs.length} new message(s)")
            new_msgs.each do |msg|
              log_message(team_name: team_name, channel_name: channel_name, msg: msg)
              store_channel_message_trace(team_name: team_name, channel_name: channel_name, msg: msg) if memory_available?
            end

            latest = new_msgs.map { |m| m['createdDateTime'] }.compact.max
            @channel_hwm[channel_id] = latest if latest
          end

          def filter_new_messages(channel_id:, messages:)
            hwm = @channel_hwm[channel_id]
            return messages unless hwm

            messages.select { |m| m['createdDateTime'].to_s > hwm }
          end

          def log_message(team_name:, channel_name:, msg:)
            sender  = msg.dig('from', 'user', 'displayName') || 'Unknown'
            content = (msg.dig('body', 'content') || '').gsub(/<[^>]+>/, '').strip
            snippet = content.length > 100 ? "#{content[0, 100]}..." : content
            log_info("  [#{team_name}] ##{channel_name} | #{sender}: #{snippet}")
          end

          def max_teams
            channel_setting(:max_teams, DEFAULT_MAX_TEAMS)
          end

          def max_channels_per_team
            channel_setting(:max_channels_per_team, DEFAULT_MAX_CHANNELS)
          end

          def channel_setting(key, default)
            return default unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :channels, key) || default
          rescue StandardError
            default
          end

          def store_channel_message_trace(team_name:, channel_name:, msg:)
            sender = msg.dig('from', 'user', 'displayName') || 'Unknown'
            content = (msg.dig('body', 'content') || '').gsub(/<[^>]+>/, '').strip
            memory_runner.store_trace(
              type:            :episodic,
              content_payload: "#{sender} in #{team_name}/##{channel_name}: #{content}"[0, 5000],
              domain_tags:     ['teams', 'channel', "team:#{team_name}", "channel:#{channel_name}", "sender:#{sender}"],
              origin:          :direct_experience,
              confidence:      0.7
            )
          rescue StandardError => e
            log_error("Failed to store channel message trace: #{e.message}")
          end

          def log_debug(msg)
            Legion::Logging.debug("[Teams::ChannelPoller] #{msg}") if defined?(Legion::Logging)
          end

          def log_info(msg)
            Legion::Logging.info("[Teams::ChannelPoller] #{msg}") if defined?(Legion::Logging)
          end

          def log_error(msg)
            Legion::Logging.error("[Teams::ChannelPoller] #{msg}") if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
