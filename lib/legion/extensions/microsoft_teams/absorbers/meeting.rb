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

            subject = meeting['subject'] || meeting[:subject] || 'untitled meeting'
            meeting_id = meeting['id'] || meeting[:id]
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
            response = Runners::Meetings.get_meeting_by_join_url(join_url: url)
            return nil unless response.is_a?(Hash)

            body = response[:result]
            return nil unless body.is_a?(Hash)

            items = body['value'] || body[:value]
            return nil unless items.is_a?(Array) && !items.empty?

            items.first
          rescue StandardError => e
            Legion::Logging.warn("Could not resolve meeting: #{e.message}") if defined?(Legion::Logging)
            nil
          end

          def ingest_transcript(meeting_id, subject, results)
            report_progress(message: 'fetching transcripts', percent: 20)
            transcripts_response = Runners::Transcripts.list_transcripts(meeting_id: meeting_id)
            transcripts_body     = transcripts_response.is_a?(Hash) ? transcripts_response[:result] : nil
            return unless transcripts_body.is_a?(Hash)

            transcript_items = transcripts_body['value'] || transcripts_body[:value]
            return unless transcript_items.is_a?(Array) && transcript_items.any?

            transcript_items.each do |t|
              transcript_id = t['id'] || t[:id]
              next unless transcript_id

              report_progress(message: "pulling transcript #{transcript_id}", percent: 40)
              vtt_result = Runners::Transcripts.get_transcript_content(
                meeting_id: meeting_id, transcript_id: transcript_id, format: :vtt
              )
              vtt = vtt_result.is_a?(Hash) ? vtt_result[:result] : vtt_result
              next unless vtt.is_a?(String) && !vtt.empty?

              absorb_to_knowledge(
                content:      vtt,
                tags:         ['meeting', 'transcript', subject],
                source_file:  "teams://meetings/#{meeting_id}/transcripts/#{transcript_id}",
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
            return unless insights.is_a?(Hash)

            body  = insights[:result] || insights
            items = body.is_a?(Hash) ? (body['value'] || body[:value]) : nil
            return unless items.is_a?(Array) && items.any?

            items.each do |item|
              content    = (item.is_a?(Hash) ? (item['content'] || item[:content]) : nil) || item.to_s
              insight_id = item.is_a?(Hash) ? (item['id'] || item[:id]) : nil
              absorb_to_knowledge(
                content:      content,
                tags:         ['meeting', 'ai-insight', 'action-item', subject],
                source_file:  "teams://meetings/#{meeting_id}/insights/#{insight_id}",
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
            participants = meeting.dig('participants', 'attendees') || meeting.dig(:participants, :attendees)
            return unless participants.is_a?(Array) && participants.any?

            names = participants.filter_map do |p|
              p.dig('identity', 'user', 'displayName') || p.dig(:identity, :user, :displayName)
            end
            return if names.empty?

            meeting_id = meeting['id'] || meeting[:id]
            absorb_raw(
              content:      "Meeting participants for '#{subject}': #{names.join(', ')}",
              tags:         ['meeting', 'participants', subject],
              content_type: 'meeting_participants',
              metadata:     { meeting_id: meeting_id, participant_count: names.length }
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
