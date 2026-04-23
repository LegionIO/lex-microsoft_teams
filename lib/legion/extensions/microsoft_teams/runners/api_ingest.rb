# frozen_string_literal: true

require 'json'
require 'digest'
require 'legion/extensions/microsoft_teams/helpers/client'
require 'legion/extensions/microsoft_teams/helpers/permission_guard'
require 'legion/extensions/microsoft_teams/helpers/high_water_mark'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module ApiIngest
          include Helpers::Client
          include Helpers::PermissionGuard
          include Helpers::HighWaterMark
          extend self

          # Fetch top contacts via /me/people, then pull recent messages from
          # their 1:1 chats. Stores each message as an individual memory trace
          # (same format as CacheIngest) with dedup by content hash.
          #
          # Requires a delegated token with Chat.Read and People.Read scopes.
          def ingest_api(token:, top_people: 15, message_depth: 50, skip_bots: true, imprint_active: false, **) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
            return error_result('lex-memory not loaded') unless memory_available?
            return error_result('no token provided') unless token && !token.empty?

            restore_hwm_from_traces

            people = fetch_top_people(token: token, top: top_people)
            log.debug("ApiIngest: fetched #{people.size} top people")
            return error_result('people endpoint denied or empty') if people.empty?

            chats = fetch_one_on_one_chats(token: token)
            log.debug("ApiIngest: fetched #{chats.size} oneOnOne chats")
            return error_result('no 1:1 chats found') if chats.empty?

            existing_hashes = load_existing_hashes
            conn = graph_connection(token: token)
            stored = 0
            skipped = 0
            people_ingested = 0
            thread_groups = Hash.new { |h, k| h[k] = [] }
            person_texts = Hash.new { |h, k| h[k] = [] }

            people.each do |person|
              chat = match_chat_to_person(chats: chats, person: person, conn: conn)
              unless chat
                log.debug("ApiIngest: no chat match for #{person['displayName']} " \
                          "(email=#{person.dig('scoredEmailAddresses', 0, 'address')}, id=#{person['id']})")
                next
              end
              log.info("ApiIngest: matched #{person['displayName']} to chat #{chat['id']}")

              messages = fetch_chat_messages(conn: conn, chat_id: chat['id'], depth: message_depth)
              next if messages.empty?

              msg_stored = 0
              messages.each do |msg|
                next if skip_bots && bot_message_graph?(msg)

                text = extract_body_text(msg)
                next if text.length < 5

                content_hash = msg['id'] || Digest::SHA256.hexdigest(text)[0, 16]
                if existing_hashes.include?(content_hash)
                  skipped += 1
                  next
                end

                trace_result = store_graph_message(msg, text, person, chat['id'],
                                                   content_hash:   content_hash,
                                                   imprint_active: imprint_active)
                if trace_result
                  stored += 1
                  msg_stored += 1
                  existing_hashes << content_hash
                  thread_groups[chat['id']] << trace_result[:trace_id]
                  person_texts[person['displayName']] << text
                else
                  skipped += 1
                end
              end

              next unless msg_stored.positive?

              people_ingested += 1
              update_extended_hwm(chat_id: chat['id'],
                                  last_message_at: messages.filter_map { |m| m['createdDateTime'] }.max,
                                  new_message_count: msg_stored, ingested: true)
            end

            coactivate_thread_traces(thread_groups)
            flush_trace_store if stored.positive?
            apollo_results = publish_to_apollo(person_texts) if stored.positive?

            { result: { stored: stored, skipped: skipped, people_ingested: people_ingested,
                        people_found: people.length, chats_found: chats.length,
                        apollo: apollo_results } }
          rescue StandardError => e
            log_msg = "ApiIngest failed: #{e.class} — #{e.message}"
            log.error(log_msg)
            { result: { stored: stored || 0, skipped: skipped || 0, error: e.message } }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)

          MAX_CHAT_PAGES = 10

          private

          def fetch_top_people(token:, top:)
            return [] if permission_denied?('/me/people')

            conn = graph_connection(token: token)
            resp = conn.get('me/people', { '$top' => top })

            log.debug("ApiIngest: fetch_top_people status=#{resp.status} count=#{(resp.body || {}).fetch('value', []).size}")
            if resp.status == 403
              record_denial('/me/people', resp.body.dig('error', 'message') || 'Forbidden')
              return []
            end

            people = (resp.body || {}).fetch('value', [])
            people.sort_by { |p| -(p.dig('scoredEmailAddresses', 0, 'relevanceScore') || 0) }
          rescue StandardError => e
            log.warn("ApiIngest: fetch_top_people failed: #{e.message}")
            []
          end

          def fetch_one_on_one_chats(token:)
            conn = graph_connection(token: token)
            all_chats = []
            url = 'me/chats'
            params = { '$top' => 50 }
            pages = 0

            loop do
              resp = conn.get(url, params)
              body = resp.body || {}
              chats = body.fetch('value', [])
              all_chats.concat(chats)
              pages += 1

              next_link = body['@odata.nextLink']
              break unless next_link
              break if pages >= MAX_CHAT_PAGES

              url = next_link
              params = {}
            end

            allowed_types = %w[oneOnOne group meeting]
            filtered = all_chats.select { |c| allowed_types.include?(c['chatType']) }
            log.info("ApiIngest: fetched #{all_chats.size} chats (#{pages} pages), #{filtered.size} eligible (1:1/group/meeting)")
            filtered
          rescue StandardError => e
            log.warn("ApiIngest: fetch_chats failed: #{e.message}")
            []
          end

          def match_chat_to_person(chats:, person:, conn:)
            email = person.dig('scoredEmailAddresses', 0, 'address')&.downcase
            display_name = person['displayName']&.downcase
            user_id = person['id']
            return nil unless email || user_id || display_name

            chats.find do |chat|
              members_resp = conn.get("chats/#{chat['id']}/members")
              members = (members_resp.body || {}).fetch('value', [])
              members.any? do |m|
                match_member?(m, email: email, user_id: user_id, display_name: display_name)
              end
            end
          rescue StandardError => e
            log.debug("ApiIngest: match_chat_to_person failed: #{e.message}")
            nil
          end

          def match_member?(member, email:, user_id:, display_name:)
            return true if email && member['email']&.downcase == email
            return true if user_id && member['userId'] == user_id
            return true if email && member.dig('additionalData', 'email')&.downcase == email

            member_name = member['displayName']&.downcase
            return true if display_name && member_name && member_name == display_name

            false
          end

          def fetch_chat_messages(conn:, chat_id:, depth: 50)
            hwm = get_extended_hwm(chat_id: chat_id)
            params = { '$top' => depth, '$orderby' => 'createdDateTime desc' }
            params['$filter'] = "createdDateTime gt #{hwm[:last_message_at]}" if hwm&.dig(:last_message_at)

            resp = conn.get("chats/#{chat_id}/messages", params)
            log.debug("ApiIngest: fetch_messages chat=#{chat_id} count=#{(resp.body || {}).fetch('value', []).size}")
            (resp.body || {}).fetch('value', [])
          rescue StandardError => e
            log.warn("ApiIngest: fetch_messages failed for #{chat_id}: #{e.message}")
            []
          end

          def extract_body_text(msg)
            html = msg.dig('body', 'content') || ''
            strip_html(html)
          end

          def strip_html(html)
            return '' if html.nil? || html.empty?

            html.gsub(/<[^>]+>/, ' ').gsub('&nbsp;', ' ').gsub('&amp;', '&')
                .gsub('&lt;', '<').gsub('&gt;', '>').gsub('&quot;', '"')
                .gsub(/\s+/, ' ').strip
          end

          def bot_message_graph?(msg)
            app = msg.dig('from', 'application')
            return true if app && app['id']

            user_type = msg.dig('from', 'user', 'userIdentityType')
            %w[anonymousGuest azureCommunicationServicesUser].include?(user_type)
          end

          def store_graph_message(msg, text, person, chat_id, content_hash:, imprint_active: false)
            sender = msg.dig('from', 'user', 'displayName') || person['displayName'] || 'Unknown'
            compose_time = msg['createdDateTime']

            domain_tags = build_graph_domain_tags(sender: sender, chat_id: chat_id,
                                                  compose_time: compose_time, content_hash: content_hash,
                                                  message_id: msg['id'])

            memory_runner.store_trace(
              type:                :episodic,
              content_payload:     text,
              domain_tags:         domain_tags,
              origin:              :direct_experience,
              confidence:          0.7,
              emotional_valence:   0.1,
              emotional_intensity: 0.2,
              imprint_active:      imprint_active
            )
          rescue StandardError => e
            log.warn("ApiIngest: store trace failed: #{e.message}")
            nil
          end

          def build_graph_domain_tags(sender:, chat_id:, compose_time:, content_hash:, message_id:)
            tags = %w[teams graph_api]
            tags << "sender:#{sender}"
            tags << "peer:#{sender}"
            tags << "chat_id:#{chat_id}" if chat_id
            tags << "hash:#{content_hash}" if content_hash
            tags << "time:#{compose_time}" if compose_time
            tags << "msg_id:#{message_id}" if message_id
            tags
          end

          def load_existing_hashes
            store = Legion::Extensions::Agentic::Memory::Trace.shared_store
            hashes = Set.new
            store.all_traces(min_strength: 0.0).each do |trace|
              trace[:domain_tags]&.each do |tag|
                hashes << tag.delete_prefix('hash:') if tag.start_with?('hash:')
              end
            end
            hashes
          rescue StandardError => e
            log.debug("ApiIngest: load_existing_hashes failed: #{e.message}")
            Set.new
          end

          def memory_available?
            defined?(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def memory_runner
            @memory_runner ||= Object.new.extend(Legion::Extensions::Agentic::Memory::Trace::Runners::Traces)
          end

          def flush_trace_store
            store = Legion::Extensions::Agentic::Memory::Trace.shared_store
            store.flush if store.respond_to?(:flush)
          rescue StandardError => e
            log.warn("ApiIngest: flush failed: #{e.message}")
          end

          def coactivate_thread_traces(thread_groups)
            return unless defined?(Legion::Extensions::Agentic::Memory::Trace::Helpers::Store)

            store = Legion::Extensions::Agentic::Memory::Trace.shared_store
            thread_groups.each_value do |trace_ids|
              next if trace_ids.length < 2

              trace_ids.each_cons(2) do |id_a, id_b|
                store.record_coactivation(id_a, id_b)
              rescue StandardError => e
                log.debug("ApiIngest: coactivation link failed for #{id_a}/#{id_b}: #{e.message}")
                nil
              end
            end
          rescue StandardError => e
            log.debug("ApiIngest: coactivation skipped: #{e.message}")
          end

          def publish_to_apollo(person_texts)
            return { skipped: true, reason: :apollo_unavailable } unless apollo_available?

            ingested = 0
            entities_found = 0
            knowledge_runner = apollo_knowledge_runner

            person_texts.each do |person_name, texts|
              combined = texts.join("\n\n")
              next if combined.length < 20

              result = knowledge_runner.handle_ingest(
                content:         "Conversation observations from #{person_name}: #{combined[0, 2000]}",
                content_type:    :observation,
                tags:            ['teams', 'graph_api', "peer:#{person_name}"],
                source_agent:    'teams-api-ingest',
                source_provider: 'microsoft',
                source_channel:  'teams_graph_api',
                context:         { person: person_name, message_count: texts.length }
              )
              ingested += 1 if result[:success]

              entity_result = extract_and_ingest_entities(combined, person_name, knowledge_runner)
              entities_found += entity_result[:count] if entity_result[:success]
            end

            { ingested: ingested, entities_found: entities_found }
          rescue StandardError => e
            log.warn("ApiIngest: publish_to_apollo failed: #{e.message}")
            { skipped: true, reason: :error, error: e.message }
          end

          def extract_and_ingest_entities(text, person_name, knowledge_runner)
            return { success: false, count: 0 } unless entity_extractor_available?

            extractor = Object.new.extend(Legion::Extensions::Apollo::Runners::EntityExtractor)
            result = extractor.extract_entities(text: text[0, 4000])
            return { success: false, count: 0 } unless result[:success] && result[:entities]&.any?

            result[:entities].each do |entity|
              knowledge_runner.handle_ingest(
                content:         "#{entity[:type]}: #{entity[:name]}",
                content_type:    entity[:type] == 'person' ? :association : :concept,
                tags:            ['teams', 'entity', "entity_type:#{entity[:type]}", "peer:#{person_name}"],
                source_agent:    'teams-entity-extractor',
                source_provider: 'microsoft',
                source_channel:  'teams_graph_api',
                context:         { entity_name: entity[:name], entity_type: entity[:type],
                                   confidence: entity[:confidence], extracted_from: person_name }
              )
            end

            { success: true, count: result[:entities].length }
          rescue StandardError => e
            log.debug("ApiIngest: entity extraction failed for #{person_name}: #{e.message}")
            { success: false, count: 0 }
          end

          def apollo_available?
            defined?(Legion::Extensions::Apollo::Runners::Knowledge) &&
              defined?(Legion::Data::Model::ApolloEntry)
          end

          def entity_extractor_available?
            defined?(Legion::Extensions::Apollo::Runners::EntityExtractor) &&
              defined?(Legion::LLM) && Legion::LLM.respond_to?(:started?) && Legion::LLM.started?
          end

          def apollo_knowledge_runner
            @apollo_knowledge_runner ||= Object.new.extend(Legion::Extensions::Apollo::Runners::Knowledge)
          end

          def error_result(message)
            { result: { stored: 0, skipped: 0, error: message } }
          end
        end
      end
    end
  end
end
