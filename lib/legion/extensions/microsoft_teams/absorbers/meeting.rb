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

            subject    = meeting['subject'] || meeting[:subject] || 'untitled meeting'
            meeting_id = meeting['id'] || meeting[:id]
            return { success: false, error: 'meeting has no id' } if meeting_id.nil? || meeting_id.to_s.empty?

            results = { meeting_id: meeting_id, subject: subject, chunks: 0 }

            ingest_transcript(meeting_id, subject, results)
            ingest_ai_insights(meeting_id, subject, results)
            ingest_participants(meeting, subject, results)

            report_progress(message: 'done', percent: 100)
            results.merge(success: true)
          rescue StandardError => e
            log.error("Meeting absorber failed: #{e.message}")
            { success: false, error: e.message }
          end

          private

          def meetings_runner
            @meetings_runner ||= Object.new.extend(Runners::Meetings)
          end

          def transcripts_runner
            @transcripts_runner ||= Object.new.extend(Runners::Transcripts)
          end

          def ai_insights_runner
            @ai_insights_runner ||= Object.new.extend(Runners::AiInsights)
          end

          def graph_token
            return @graph_token if defined?(@graph_token)

            @graph_token = begin
              Helpers::TokenCache.instance.cached_graph_token if defined?(Helpers::TokenCache)
            rescue StandardError
              nil
            end
          end

          def resolve_meeting(url)
            report_progress(message: 'looking up meeting by join URL', percent: 5)
            response = meetings_runner.get_meeting_by_join_url(join_url: url, token: graph_token)
            return nil unless response.is_a?(Hash)

            body = response[:result]
            return nil unless body.is_a?(Hash)

            items = body['value'] || body[:value]
            return nil unless items.is_a?(Array) && !items.empty?

            items.first
          rescue StandardError => e
            log.warn("Could not resolve meeting: #{e.message}")
            nil
          end

          def ingest_transcript(meeting_id, subject, results)
            report_progress(message: 'fetching transcripts', percent: 20)
            transcripts_response = transcripts_runner.list_transcripts(meeting_id: meeting_id, token: graph_token)
            transcripts_body     = transcripts_response.is_a?(Hash) ? transcripts_response[:result] : nil
            return unless transcripts_body.is_a?(Hash)

            transcript_items = transcripts_body['value'] || transcripts_body[:value]
            return unless transcript_items.is_a?(Array) && transcript_items.any?

            transcript_items.each do |t|
              transcript_id = t['id'] || t[:id]
              next unless transcript_id

              report_progress(message: "pulling transcript #{transcript_id}", percent: 40)
              vtt_result = transcripts_runner.get_transcript_content(
                meeting_id: meeting_id, transcript_id: transcript_id, format: :vtt, token: graph_token
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
            log.warn("Transcript ingest failed: #{e.message}")
          end

          def ingest_ai_insights(meeting_id, subject, results)
            report_progress(message: 'fetching AI insights', percent: 60)
            insights = ai_insights_runner.list_meeting_ai_insights(meeting_id: meeting_id, token: graph_token)
            return unless insights.is_a?(Hash)

            body  = insights[:result] || insights
            items = body.is_a?(Hash) ? (body['value'] || body[:value]) : nil
            return unless items.is_a?(Array) && items.any?

            items.each { |item| absorb_insight_item(item, meeting_id, subject, results) }
          rescue StandardError => e
            log.warn("AI insights ingest failed: #{e.message}")
          end

          def absorb_insight_item(item, meeting_id, subject, results)
            return unless item.is_a?(Hash)

            insight_id   = item['id'] || item[:id]
            action_items = item['actionItems'] || item[:actionItems] || []
            return if action_items.empty?

            content = action_items.filter_map { |a| a.is_a?(Hash) ? (a['text'] || a[:text]) : a.to_s }.join("\n")
            return if content.empty?

            absorb_to_knowledge(
              content:      content,
              tags:         ['meeting', 'ai-insight', 'action-item', subject],
              source_file:  "teams://meetings/#{meeting_id}/insights/#{insight_id}",
              heading:      "AI Insight: #{subject}",
              content_type: 'meeting_insight'
            )
            results[:chunks] += 1
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
            log.warn("Participant ingest failed: #{e.message}")
          end
        end
      end
    end
  end
end
