# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Actor
        class MeetingIngest < Legion::Extensions::Actors::Every
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          DEFAULT_INGEST_INTERVAL = 300

          def runner_class    = self.class
          def runner_function = 'manual'
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
            rescue StandardError => e
              handle_exception(e, level: :debug, operation: 'MeetingIngest#time')
              {}
            end
            settings.dig(:meetings, :ingest_interval) || DEFAULT_INGEST_INTERVAL
          end

          def enabled?
            Legion::Extensions::Identity::Entra::Helpers::TokenManager.respond_to?(:load_token)
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: 'MeetingIngest#enabled?')
            false
          end

          def memory_available?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def memory_runner
            @memory_runner ||= Object.new.extend(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def manual
            log.info('MeetingIngest polling for meetings')
            token = Legion::Extensions::Identity::Entra::Helpers::TokenManager.load_token(:delegated)
            return if token.nil?

            conn = graph_connection(token: token)
            response = conn.get("#{user_path('me')}/onlineMeetings")
            meetings = response.body&.dig('value') || []
            log.info("MeetingIngest found #{meetings.length} online meeting(s)")

            meetings.each do |meeting|
              meeting_id = meeting['id']
              next if @processed_meetings.include?(meeting_id)

              begin
                process_meeting(meeting_id: meeting_id, subject: meeting['subject'], token: token)
                @processed_meetings.add(meeting_id)
              rescue StandardError => e
                handle_exception(e, level: :error, operation: 'MeetingIngest#manual',
                                 meeting_id: meeting_id)
              end
            end
          rescue StandardError => e
            handle_exception(e, level: :error, operation: 'MeetingIngest#manual')
          end

          private

          def process_meeting(meeting_id:, subject:, token:)
            log.debug("MeetingIngest#process_meeting meeting_id=#{meeting_id} subject=#{subject}")
            conn = graph_connection(token: token)

            transcripts = fetch_transcripts(conn: conn, meeting_id: meeting_id)
            log.info("MeetingIngest '#{subject}' (#{meeting_id}): #{transcripts.length} transcript(s)")

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
            log.debug("MeetingIngest#fetch_transcripts meeting_id=#{meeting_id}")
            response = conn.get("#{user_path('me')}/onlineMeetings/#{meeting_id}/transcripts")
            response.body&.dig('value') || []
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'MeetingIngest#fetch_transcripts',
                             meeting_id: meeting_id)
            []
          end

          def fetch_and_log_transcript_content(conn:, meeting_id:, subject:, token:, transcript:) # rubocop:disable Lint/UnusedMethodArgument
            tid = transcript['id']
            log.debug("MeetingIngest#fetch_and_log_transcript_content meeting_id=#{meeting_id} transcript_id=#{tid}")
            content_conn = graph_connection(token: token)
            content_response = content_conn.get(
              "#{user_path('me')}/onlineMeetings/#{meeting_id}/transcripts/#{tid}/content",
              {},
              { 'Accept' => 'text/vtt' }
            )
            content = content_response.body.to_s
            preview = content[0, 200]
            log.debug("MeetingIngest '#{subject}' transcript #{tid}: #{preview}")
            store_transcript_trace(meeting_id: meeting_id, subject: subject, transcript_id: tid, content: content) if memory_available?
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'MeetingIngest#fetch_and_log_transcript_content',
                             meeting_id: meeting_id, transcript_id: tid)
          end

          def fetch_and_log_ai_insights(conn:, meeting_id:, subject:)
            log.debug("MeetingIngest#fetch_and_log_ai_insights meeting_id=#{meeting_id}")
            response = conn.get("#{user_path('me')}/onlineMeetings/#{meeting_id}/aiInsights")
            insights = response.body&.dig('value') || []
            log.info("MeetingIngest '#{subject}' (#{meeting_id}): #{insights.length} AI insight(s)")

            insights.each do |insight|
              action_items = insight['actionItems'] || []
              next if action_items.empty?

              log.info("MeetingIngest '#{subject}' AI insight action items (#{action_items.length}):")
              action_items.each do |item|
                log.info("  - #{item['text'] || item.inspect}")
              end

              store_insight_trace(meeting_id: meeting_id, subject: subject, insight: insight) if memory_available?
            end
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'MeetingIngest#fetch_and_log_ai_insights',
                             meeting_id: meeting_id)
          end

          def store_transcript_trace(meeting_id:, subject:, transcript_id:, content:) # rubocop:disable Lint/UnusedMethodArgument
            log.debug("MeetingIngest#store_transcript_trace meeting_id=#{meeting_id} transcript_id=#{transcript_id}")
            memory_runner.store_trace(
              type:            :episodic,
              content_payload: content[0, 10_000],
              domain_tags:     ['teams', 'transcript', "meeting:#{meeting_id}", "transcript:#{transcript_id}"],
              origin:          :direct_experience,
              confidence:      0.9
            )
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'MeetingIngest#store_transcript_trace',
                             meeting_id: meeting_id, transcript_id: transcript_id)
          end

          def store_insight_trace(meeting_id:, subject:, insight:) # rubocop:disable Lint/UnusedMethodArgument
            log.debug("MeetingIngest#store_insight_trace meeting_id=#{meeting_id}")
            memory_runner.store_trace(
              type:            :semantic,
              content_payload: insight.to_s,
              domain_tags:     ['teams', 'ai-insight', "meeting:#{meeting_id}"],
              origin:          :inferred,
              confidence:      0.8
            )
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'MeetingIngest#store_insight_trace',
                             meeting_id: meeting_id)
          end
        end
      end
    end
  end
end
