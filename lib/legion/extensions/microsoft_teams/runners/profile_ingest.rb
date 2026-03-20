# frozen_string_literal: true

require 'json'
require 'legion/extensions/microsoft_teams/helpers/client'
require 'legion/extensions/microsoft_teams/helpers/permission_guard'
require 'legion/extensions/microsoft_teams/helpers/high_water_mark'
require 'legion/extensions/microsoft_teams/helpers/transform_definitions'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module ProfileIngest
          include Helpers::Client
          include Helpers::PermissionGuard
          include Helpers::HighWaterMark

          def full_ingest(token:, top_people: 10, message_depth: 50, **)
            self_result = ingest_self(token: token)
            people_result = ingest_people(token: token, top: 25)
            people = people_result[:skipped] ? [] : (people_result[:people] || [])
            conv_result = ingest_conversations(token: token, people: people,
                                               top_people: top_people, message_depth: message_depth)
            teams_result = ingest_teams_and_meetings(token: token)

            { self: self_result, people: people_result, conversations: conv_result, teams: teams_result }
          end

          def ingest_self(token:, **)
            conn = graph_connection(token: token)
            profile = conn.get('me').body

            memory_runner.store_trace(
              type:            :identity,
              content_payload: ::JSON.dump(profile),
              domain_tags:     %w[teams self owner],
              confidence:      1.0,
              origin:          :direct_experience
            )

            presence = begin
              conn.get('me/presence').body
            rescue StandardError
              {}
            end
            unless presence.empty?
              memory_runner.store_trace(
                type:            :sensory,
                content_payload: ::JSON.dump(presence),
                domain_tags:     %w[teams presence self],
                confidence:      0.8,
                origin:          :direct_experience
              )
            end

            { profile: profile, presence: presence }
          rescue StandardError => e
            { error: e.message }
          end

          def ingest_people(token:, top: 25, **)
            return { skipped: true, reason: :permission_denied } if permission_denied?('/me/people')

            conn = graph_connection(token: token)
            resp = conn.get('me/people', { '$top' => top })

            if resp.respond_to?(:status) && resp.status == 403
              record_denial('/me/people', resp.body.dig('error', 'message') || 'Forbidden')
              return { skipped: true, reason: :permission_denied }
            end

            people = (resp.body || {}).fetch('value', [])
            people.sort_by! { |p| -(p.dig('scoredEmailAddresses', 0, 'relevanceScore') || 0) }

            people.each do |person|
              name = person['displayName'] || 'Unknown'
              memory_runner.store_trace(
                type:            :semantic,
                content_payload: ::JSON.dump(person.slice('displayName', 'jobTitle', 'department',
                                                          'officeLocation', 'scoredEmailAddresses')),
                domain_tags:     ['teams', 'peer', "peer:#{name}"],
                confidence:      0.7,
                origin:          :direct_experience
              )
            end

            { people: people, count: people.length }
          rescue StandardError => e
            { error: e.message, skipped: false }
          end

          def ingest_conversations(token:, people:, top_people: 10, message_depth: 50, **)
            return { ingested: 0 } if people.empty?

            conn = graph_connection(token: token)
            chats_resp = conn.get('me/chats', { '$top' => 50 })
            chats = (chats_resp.body || {}).fetch('value', [])
            ingested = 0

            people.first(top_people).each do |person|
              email = person.dig('scoredEmailAddresses', 0, 'address')
              next unless email

              chat = find_chat_for_person(chats: chats, email: email, conn: conn)
              next unless chat

              messages = fetch_new_messages(conn: conn, chat_id: chat['id'], depth: message_depth)
              next if messages.empty?

              extraction = extract_conversation(messages: messages, peer_name: person['displayName'])
              next unless extraction

              memory_runner.store_trace(
                type:            :episodic,
                content_payload: ::JSON.dump({
                                               peer: person['displayName'], chat_id: chat['id'],
                  summary: extraction, last_active: messages.first&.dig('createdDateTime')
                                             }),
                domain_tags:     ['teams', 'conversation', "peer:#{person['displayName']}"],
                confidence:      0.6,
                origin:          :direct_experience
              )

              update_extended_hwm(chat_id: chat['id'],
                                  last_message_at: messages.map { |m| m['createdDateTime'] }.max,
                                  new_message_count: messages.length, ingested: true)
              persist_hwm_as_trace(chat_id: chat['id'])
              ingested += 1
            end

            { ingested: ingested }
          rescue StandardError => e
            { error: e.message, ingested: ingested || 0 }
          end

          def ingest_teams_and_meetings(token:, **)
            conn = graph_connection(token: token)
            teams_count = 0

            unless permission_denied?('/me/joinedTeams')
              teams_resp = conn.get('me/joinedTeams')
              teams = (teams_resp.body || {}).fetch('value', [])

              teams.each do |team|
                members_resp = conn.get("teams/#{team['id']}/members")
                members = (members_resp.body || {}).fetch('value', [])
                memory_runner.store_trace(
                  type:            :semantic,
                  content_payload: ::JSON.dump({ team: team['displayName'], member_count: members.length,
                                                 members: members.map { |m| m['displayName'] } }),
                  domain_tags:     ['teams', 'org', "team:#{team['displayName']}"],
                  confidence:      0.8,
                  origin:          :direct_experience
                )
                teams_count += 1
              end
            end

            meetings_count = 0
            unless permission_denied?('/me/onlineMeetings')
              meetings_resp = conn.get('me/onlineMeetings')
              meetings = (meetings_resp.body || {}).fetch('value', [])
              meetings.each do |meeting|
                memory_runner.store_trace(
                  type:            :episodic,
                  content_payload: ::JSON.dump(meeting.slice('subject', 'startDateTime', 'endDateTime',
                                                             'participants')),
                  domain_tags:     %w[teams meeting],
                  confidence:      0.5,
                  origin:          :direct_experience
                )
                meetings_count += 1
              end
            end

            { teams: teams_count, meetings: meetings_count }
          rescue StandardError => e
            { error: e.message }
          end

          def incremental_sync(token:, top_people: 10, message_depth: 50, **)
            ingest_self(token: token)
            people_result = ingest_people(token: token, top: 25)
            people = people_result[:skipped] ? [] : (people_result[:people] || [])

            return { refreshed: true, conversations: 0 } if people.empty?

            ingest_conversations(token: token, people: people,
                                 top_people: top_people, message_depth: message_depth)
          end

          private

          def find_chat_for_person(chats:, email:, conn:)
            chats.select { |c| c['chatType'] == 'oneOnOne' }.find do |chat|
              members_resp = conn.get("chats/#{chat['id']}/members")
              members = (members_resp.body || {}).fetch('value', [])
              members.any? { |m| m['email']&.downcase == email.downcase }
            end
          rescue StandardError
            nil
          end

          def fetch_new_messages(conn:, chat_id:, depth: 50)
            hwm = get_extended_hwm(chat_id: chat_id)
            params = { '$top' => depth, '$orderby' => 'createdDateTime desc' }
            params['$filter'] = "createdDateTime gt #{hwm[:last_message_at]}" if hwm&.dig(:last_message_at)

            resp = conn.get("chats/#{chat_id}/messages", params)
            (resp.body || {}).fetch('value', [])
          rescue StandardError
            []
          end

          def extract_conversation(messages:, peer_name:)
            return nil if messages.empty?

            definition = Helpers::TransformDefinitions.conversation_extract
            text = messages.map do |m|
              from = m.dig('from', 'user', 'displayName') || 'Unknown'
              "#{from}: #{m['body']&.dig('content') || ''}"
            end.join("\n")

            if defined?(Legion::Extensions::Transformer::Client)
              client = Legion::Extensions::Transformer::Client.new
              result = client.transform(text: text, **definition)
              result[:result] || result[:error] ? nil : result
            elsif defined?(Legion::LLM)
              Legion::LLM.ask(prompt: "#{definition[:prompt]}\n\nConversation with #{peer_name}:\n#{text}")
            end
          rescue StandardError
            nil
          end

          def memory_runner
            @memory_runner ||= begin
              runner = Object.new
              runner.extend(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
              runner
            end
          end
        end
      end
    end
  end
end
