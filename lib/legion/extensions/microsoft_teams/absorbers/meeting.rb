# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Absorbers
        class Meeting < Legion::Extensions::Absorbers::Base
          pattern :url, 'teams.microsoft.com/l/meetup-join/*'
          pattern :url, '*.teams.microsoft.com/meet/*'
          description 'Absorbs Teams meeting transcripts, AI insights, and participants into Apollo'

          def handle(url: nil, content: nil, metadata: {}, context: {}) # rubocop:disable Lint/UnusedMethodArgument
            report_progress(message: 'resolving meeting from link')
            meeting = resolve_meeting(url)
            return { success: false, error: 'could not resolve meeting' } unless meeting

            subject = meeting[:subject] || 'untitled meeting'
            meeting_id = meeting[:id]
            results = { meeting_id: meeting_id, subject: subject, chunks: 0 }

            ingest_transcript(meeting_id, subject, results)
            ingest_ai_insights(meeting_id, subject, results)
            ingest_participants(meeting, subject, results)

            report_progress(message: 'done', percent: 100)
            results.merge(success: true)
          rescue StandardError => e
            Legion::Logging.error("Meeting absorber failed: #{e.message}") if defined?(Legion::Logging)
            { success: false, error: e.message }
          end

          private

          def resolve_meeting(url)
            report_progress(message: 'looking up meeting by join URL', percent: 5)
            result = Runners::Meetings.get_meeting_by_join_url(join_url: url)
            result.is_a?(Hash) && result[:id] ? result : nil
          rescue StandardError => e
            Legion::Logging.warn("Could not resolve meeting: #{e.message}") if defined?(Legion::Logging)
            nil
          end

          def ingest_transcript(meeting_id, subject, results)
            report_progress(message: 'fetching transcripts', percent: 20)
            transcripts = Runners::Transcripts.list_transcripts(meeting_id: meeting_id)
            return unless transcripts.is_a?(Hash) && transcripts[:value]&.any?

            transcripts[:value].each do |t|
              report_progress(message: "pulling transcript #{t[:id]}", percent: 40)
              vtt = Runners::Transcripts.get_transcript_content(
                meeting_id: meeting_id, transcript_id: t[:id], format: :vtt
              )
              next unless vtt.is_a?(String) && !vtt.empty?

              absorb_to_knowledge(
                content:      vtt,
                tags:         ['meeting', 'transcript', subject],
                source_file:  "teams://meetings/#{meeting_id}/transcripts/#{t[:id]}",
                heading:      "Transcript: #{subject}",
                content_type: 'meeting_transcript'
              )
              results[:chunks] += 1
            end
          rescue StandardError => e
            Legion::Logging.warn("Transcript ingest failed: #{e.message}") if defined?(Legion::Logging)
          end

          def ingest_ai_insights(meeting_id, subject, results)
            report_progress(message: 'fetching AI insights', percent: 60)
            insights = Runners::AiInsights.list_meeting_ai_insights(meeting_id: meeting_id)
            return unless insights.is_a?(Hash) && insights[:value]&.any?

            insights[:value].each do |item|
              content = item[:content] || item.to_s
              absorb_to_knowledge(
                content:      content,
                tags:         ['meeting', 'ai-insight', 'action-item', subject],
                source_file:  "teams://meetings/#{meeting_id}/insights/#{item[:id]}",
                heading:      "AI Insight: #{subject}",
                content_type: 'meeting_insight'
              )
              results[:chunks] += 1
            end
          rescue StandardError => e
            Legion::Logging.warn("AI insights ingest failed: #{e.message}") if defined?(Legion::Logging)
          end

          def ingest_participants(meeting, subject, results)
            report_progress(message: 'recording participants', percent: 80)
            participants = meeting.dig(:participants, :attendees)
            return unless participants.is_a?(Array) && participants.any?

            names = participants.filter_map { |p| p.dig(:identity, :user, :displayName) }
            return if names.empty?

            absorb_raw(
              content:      "Meeting participants for '#{subject}': #{names.join(', ')}",
              tags:         ['meeting', 'participants', subject],
              content_type: 'meeting_participants',
              metadata:     { meeting_id: meeting[:id], participant_count: names.length }
            )
            results[:chunks] += 1
          rescue StandardError => e
            Legion::Logging.warn("Participant ingest failed: #{e.message}") if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
