# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class MeetingIngest < Legion::Extensions::Actors::Every
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          DEFAULT_INGEST_INTERVAL = 300

          def runner_class    = Legion::Extensions::MicrosoftTeams::Helpers::TokenCache
          def runner_function = 'cached_graph_token'
          def run_now?        = false
          def use_runner?     = false
          def check_subtask?  = false
          def generate_task?  = false

          def initialize(**opts)
            @processed_meetings = Set.new
            super
          end

          def time
            settings = begin
              Legion::Settings[:microsoft_teams] || {}
            rescue StandardError
              {}
            end
            settings.dig(:meetings, :ingest_interval) || DEFAULT_INGEST_INTERVAL
          end

          def enabled?
            defined?(Legion::Extensions::MicrosoftTeams::Helpers::TokenCache)
          rescue StandardError
            false
          end

          def token_cache
            Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.instance
          end

          def manual
            token = token_cache.cached_graph_token
            return if token.nil?

            conn = graph_connection(token: token)
            response = conn.get("#{user_path('me')}/onlineMeetings")
            meetings = response.body&.dig('value') || []
            log_info("Found #{meetings.length} online meeting(s)")

            meetings.each do |meeting|
              meeting_id = meeting['id']
              next if @processed_meetings.include?(meeting_id)

              begin
                process_meeting(meeting_id: meeting_id, subject: meeting['subject'], token: token)
                @processed_meetings.add(meeting_id)
              rescue StandardError => e
                log_error("Failed to process meeting #{meeting_id}: #{e.message}")
              end
            end
          rescue StandardError => e
            log_error("MeetingIngest: #{e.message}")
          end

          private

          def process_meeting(meeting_id:, subject:, token:)
            conn = graph_connection(token: token)

            transcripts = fetch_transcripts(conn: conn, meeting_id: meeting_id)
            log_info("Meeting '#{subject}' (#{meeting_id}): #{transcripts.length} transcript(s)")

            transcripts.each do |transcript|
              fetch_and_log_transcript_content(
                conn:       conn,
                meeting_id: meeting_id,
                subject:    subject,
                token:      token,
                transcript: transcript
              )
            end

            fetch_and_log_ai_insights(conn: conn, meeting_id: meeting_id, subject: subject)
          end

          def fetch_transcripts(conn:, meeting_id:)
            response = conn.get("#{user_path('me')}/onlineMeetings/#{meeting_id}/transcripts")
            response.body&.dig('value') || []
          rescue StandardError => e
            log_warn("Could not fetch transcripts for meeting #{meeting_id}: #{e.message}")
            []
          end

          def fetch_and_log_transcript_content(conn:, meeting_id:, subject:, token:, transcript:) # rubocop:disable Lint/UnusedMethodArgument
            tid = transcript['id']
            content_conn = graph_connection(token: token)
            content_response = content_conn.get(
              "#{user_path('me')}/onlineMeetings/#{meeting_id}/transcripts/#{tid}/content",
              {},
              { 'Accept' => 'text/vtt' }
            )
            content = content_response.body.to_s
            preview = content[0, 200]
            log_debug("Meeting '#{subject}' transcript #{tid}: #{preview}")
          rescue StandardError => e
            log_warn("Could not fetch transcript content #{tid} for meeting #{meeting_id}: #{e.message}")
          end

          def fetch_and_log_ai_insights(conn:, meeting_id:, subject:)
            response = conn.get("#{user_path('me')}/onlineMeetings/#{meeting_id}/aiInsights")
            insights = response.body&.dig('value') || []
            log_info("Meeting '#{subject}' (#{meeting_id}): #{insights.length} AI insight(s)")

            insights.each do |insight|
              action_items = insight['actionItems'] || []
              next if action_items.empty?

              log_info("Meeting '#{subject}' AI insight action items (#{action_items.length}):")
              action_items.each do |item|
                log_info("  - #{item['text'] || item.inspect}")
              end
            end
          rescue StandardError => e
            log_warn("Could not fetch AI insights for meeting #{meeting_id}: #{e.message}")
          end

          def log_debug(msg)
            Legion::Logging.debug("[Teams::MeetingIngest] #{msg}") if defined?(Legion::Logging)
          end

          def log_info(msg)
            Legion::Logging.info("[Teams::MeetingIngest] #{msg}") if defined?(Legion::Logging)
          end

          def log_warn(msg)
            Legion::Logging.warn("[Teams::MeetingIngest] #{msg}") if defined?(Legion::Logging)
          end

          def log_error(msg)
            Legion::Logging.error("[Teams::MeetingIngest] #{msg}") if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
