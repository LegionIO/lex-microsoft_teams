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

          def memory_available?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def memory_runner
            @memory_runner ||= Object.new.extend(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def token_cache
            Legion::Extensions::MicrosoftTeams::Helpers::TokenCache.instance
          end

          def manual
            log.info('MeetingIngest polling for meetings')
            token = token_cache.cached_graph_token
            return if token.nil?

            conn = graph_connection(token: token)
            response = conn.get("#{user_path('me')}/onlineMeetings")
            meetings = response.body&.dig('value') || []
            log.info("Found #{meetings.length} online meeting(s)")

            meetings.each do |meeting|
              meeting_id = meeting['id']
              next if @processed_meetings.include?(meeting_id)

              begin
                process_meeting(meeting_id: meeting_id, subject: meeting['subject'], token: token)
                @processed_meetings.add(meeting_id)
              rescue StandardError => e
                log.error("Failed to process meeting #{meeting_id}: #{e.message}")
              end
            end
          rescue StandardError => e
            log.error("MeetingIngest: #{e.message}")
          end

          private

          def process_meeting(meeting_id:, subject:, token:)
            conn = graph_connection(token: token)

            transcripts = fetch_transcripts(conn: conn, meeting_id: meeting_id)
            log.info("Meeting '#{subject}' (#{meeting_id}): #{transcripts.length} transcript(s)")

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
            log.warn("Could not fetch transcripts for meeting #{meeting_id}: #{e.message}")
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
            log.debug("Meeting '#{subject}' transcript #{tid}: #{preview}")
            store_transcript_trace(meeting_id: meeting_id, subject: subject, transcript_id: tid, content: content) if memory_available?
          rescue StandardError => e
            log.warn("Could not fetch transcript content #{tid} for meeting #{meeting_id}: #{e.message}")
          end

          def fetch_and_log_ai_insights(conn:, meeting_id:, subject:)
            response = conn.get("#{user_path('me')}/onlineMeetings/#{meeting_id}/aiInsights")
            insights = response.body&.dig('value') || []
            log.info("Meeting '#{subject}' (#{meeting_id}): #{insights.length} AI insight(s)")

            insights.each do |insight|
              action_items = insight['actionItems'] || []
              next if action_items.empty?

              log.info("Meeting '#{subject}' AI insight action items (#{action_items.length}):")
              action_items.each do |item|
                log.info("  - #{item['text'] || item.inspect}")
              end

              store_insight_trace(meeting_id: meeting_id, subject: subject, insight: insight) if memory_available?
            end
          rescue StandardError => e
            log.warn("Could not fetch AI insights for meeting #{meeting_id}: #{e.message}")
          end

          def store_transcript_trace(meeting_id:, subject:, transcript_id:, content:) # rubocop:disable Lint/UnusedMethodArgument
            memory_runner.store_trace(
              type:            :episodic,
              content_payload: content[0, 10_000],
              domain_tags:     ['teams', 'transcript', "meeting:#{meeting_id}", "transcript:#{transcript_id}"],
              origin:          :direct_experience,
              confidence:      0.9
            )
          rescue StandardError => e
            log.warn("Could not store transcript trace for meeting #{meeting_id}: #{e.message}")
          end

          def store_insight_trace(meeting_id:, subject:, insight:) # rubocop:disable Lint/UnusedMethodArgument
            memory_runner.store_trace(
              type:            :semantic,
              content_payload: insight.to_s,
              domain_tags:     ['teams', 'ai-insight', "meeting:#{meeting_id}"],
              origin:          :inferred,
              confidence:      0.8
            )
          rescue StandardError => e
            log.warn("Could not store insight trace for meeting #{meeting_id}: #{e.message}")
          end
        end
      end
    end
  end
end
