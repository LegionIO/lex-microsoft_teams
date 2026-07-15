# frozen_string_literal: true

require 'json'
require 'digest'
require 'set'
require 'legion/extensions/microsoft_teams/errors'
require 'legion/extensions/microsoft_teams/helpers/client'
require 'legion/extensions/microsoft_teams/helpers/graph_cache'
require 'legion/extensions/microsoft_teams/helpers/permission_guard'
require 'legion/extensions/microsoft_teams/helpers/high_water_mark'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module ApiIngest
          extend Legion::Extensions::Definitions
          include Helpers::Client
          include Helpers::PermissionGuard
          include Helpers::HighWaterMark
          include Helpers::GraphCache
          extend self

          definition :ingest_api, mcp_exposed: false

          def ingest_api(token:, top_people: 15, message_depth: 50, skip_bots: true, imprint_active: false, **) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
            log.debug("ApiIngest#ingest_api top_people=#{top_people} message_depth=#{message_depth}")
            return error_result('lex-memory not loaded') unless memory_available?
            return error_result('no token provided') unless token && !token.empty?

            @fetch_failures = 0
            restore_hwm_from_traces

            people = fetch_top_people(token: token, top: top_people)
            log.debug("ApiIngest: fetched #{people.size} top people")
            return error_result('people endpoint denied or empty') if people.empty?

            chats = fetch_one_on_one_chats(token: token)
            log.debug("ApiIngest: fetched #{chats.size} oneOnOne chats")
            return error_result('no 1:1 chats found') if chats.empty?

            existing_hashes = load_existing_hashes
            conn = graph_connection(token: token)
            chat_index = build_chat_member_index(conn: conn, chats: chats)
            stored = 0
            skipped = 0
            people_ingested = 0
            thread_groups = Hash.new { |h, k| h[k] = [] }
            person_texts = Hash.new { |h, k| h[k] = [] }

            people.each do |person|
              chat = find_chat_for_person_indexed(person: person, chat_index: chat_index)
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
                        fetch_failures: @fetch_failures,
                        apollo: apollo_results } }
          # rubocop:disable Legion/RescueLogging/NoCapture
          # Re-raise unlogged: surface the typed throttle to the caller (the
          # ApiIngest actor) so it can defer its next scheduled run by the
          # advertised retry_after. The throttle is already logged at the
          # middleware/circuit layer; folding it into an error result here
          # would hide the one signal the actor needs to stop re-charging
          # the shared Graph circuit on its fixed interval.
          rescue Errors::Throttled
            raise
            # rubocop:enable Legion/RescueLogging/NoCapture
          rescue StandardError => e
            handle_exception(e, level: :error, operation: 'ApiIngest#ingest_api')
            { result: { stored: stored || 0, skipped: skipped || 0,
                        fetch_failures: @fetch_failures || 0, error: e.message } }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)

          MAX_CHAT_PAGES = 10

          private

          def fetch_top_people(token:, top:)
            log.debug("ApiIngest#fetch_top_people top=#{top}")
            return [] if permission_denied?('/me/people')

            conn = graph_connection(token: token)
            resp = conn.get('me/people', { '$top' => top })

            log.debug("ApiIngest: fetch_top_people status=#{resp.status} count=#{(resp.body || {}).fetch('value', []).size}")
            unless (200..299).cover?(resp.status)
              error_code = resp.body&.dig('error', 'code')
              log.warn("[microsoft_teams][api_ingest] fetch_top_people non-2xx: " \
                       "status=#{resp.status} error_code=#{error_code}")
              record_denial('/me/people', resp.body&.dig('error', 'message') || 'Forbidden') if resp.status == 403
              @fetch_failures = (@fetch_failures || 0) + 1
              return []
            end

            people = (resp.body || {}).fetch('value', [])
            people.sort_by { |p| -(p.dig('scoredEmailAddresses', 0, 'relevanceScore') || 0) }
          rescue Errors::Throttled
            raise
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'ApiIngest#fetch_top_people')
            @fetch_failures = (@fetch_failures || 0) + 1
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

              unless (200..299).cover?(resp.status)
                error_code = resp.body&.dig('error', 'code')
                log.warn("[microsoft_teams][api_ingest] fetch_one_on_one_chats non-2xx: " \
                         "status=#{resp.status} error_code=#{error_code}")
                @fetch_failures = (@fetch_failures || 0) + 1
                break
              end

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
          rescue Errors::Throttled
            raise
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'ApiIngest#fetch_one_on_one_chats')
            @fetch_failures = (@fetch_failures || 0) + 1
            []
          end

          CHAT_TYPE_PRIORITY = { 'oneOnOne' => 0, 'group' => 1, 'meeting' => 2 }.freeze

          def build_chat_member_index(conn:, chats:)
            by_email = {}
            by_user_id = {}
            by_name = {}

            sorted = chats.sort_by { |c| CHAT_TYPE_PRIORITY[c['chatType']] || 99 }
            sorted.each do |chat|
              members = cached_graph_get(conn: conn, path: "chats/#{chat['id']}/members",
                                         shared: true, ttl: members_cache_ttl)
                        .then { |body| (body || {}).fetch('value', []) }
              members.each do |m|
                email = m['email']&.downcase
                alt_email = m.dig('additionalData', 'email')&.downcase
                uid = m['userId']
                name = m['displayName']&.downcase

                by_email[email] ||= chat if email
                by_email[alt_email] ||= chat if alt_email
                by_user_id[uid] ||= chat if uid
                by_name[name] ||= chat if name
              end
            end

            { email: by_email, user_id: by_user_id, name: by_name }
          rescue Errors::Throttled
            raise
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'ApiIngest#build_chat_member_index')
            @fetch_failures = (@fetch_failures || 0) + 1
            { email: {}, user_id: {}, name: {} }
          end

          def find_chat_for_person_indexed(person:, chat_index:)
            email = person.dig('scoredEmailAddresses', 0, 'address')&.downcase
            user_id = person['id']
            display_name = person['displayName']&.downcase

            chat_index[:email][email] ||
              chat_index[:user_id][user_id] ||
              chat_index[:name][display_name]
          end

          def hwm_client_side_cut(messages:, hwm:)
            return messages unless hwm&.dig(:last_message_at)

            cutoff = hwm[:last_message_at]
            seen = Set.new
            messages.take_while { |m| m['createdDateTime'] && m['createdDateTime'] > cutoff }
                    .reject { |m| !seen.add?(m['id'] || Digest::SHA256.hexdigest(m.dig('body', 'content').to_s)[0, 16]) }
          end

          def fetch_chat_messages(conn:, chat_id:, depth: 50)
            hwm = get_extended_hwm(chat_id: chat_id)
            params = { '$top' => depth, '$orderby' => 'createdDateTime desc' }

            resp = conn.get("chats/#{chat_id}/messages", params)

            unless (200..299).cover?(resp.status)
              error_code = resp.body&.dig('error', 'code')
              log.warn("[microsoft_teams][api_ingest] fetch_chat_messages non-2xx: " \
                       "chat_id=#{chat_id} status=#{resp.status} error_code=#{error_code}")
              @fetch_failures = (@fetch_failures || 0) + 1
              return []
            end

            messages = (resp.body || {}).fetch('value', [])
            messages = hwm_client_side_cut(messages: messages, hwm: hwm)
            log.debug("ApiIngest: fetch_messages chat=#{chat_id} count=#{messages.size}")
            messages
          rescue Errors::Throttled
            raise
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'ApiIngest#fetch_chat_messages',
                             chat_id: chat_id)
            @fetch_failures = (@fetch_failures || 0) + 1
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
            handle_exception(e, level: :warn, operation: 'ApiIngest#store_graph_message')
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
            handle_exception(e, level: :debug, operation: 'ApiIngest#load_existing_hashes')
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
            handle_exception(e, level: :warn, operation: 'ApiIngest#flush_trace_store')
          end

          def coactivate_thread_traces(thread_groups)
            return unless defined?(Legion::Extensions::Agentic::Memory::Trace::Helpers::Store)

            store = Legion::Extensions::Agentic::Memory::Trace.shared_store
            thread_groups.each_value do |trace_ids|
              next if trace_ids.length < 2

              trace_ids.each_cons(2) do |id_a, id_b|
                store.record_coactivation(id_a, id_b)
              rescue StandardError => e
                handle_exception(e, level: :debug, operation: 'ApiIngest#coactivate_thread_traces',
                                 id_a: id_a, id_b: id_b)
              end
            end
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: 'ApiIngest#coactivate_thread_traces')
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
                access_scope:    'private',
                context:         { person: person_name, message_count: texts.length }
              )
              ingested += 1 if result[:success]

              entity_result = extract_and_ingest_entities(combined, person_name, knowledge_runner)
              entities_found += entity_result[:count] if entity_result[:success]
            end

            { ingested: ingested, entities_found: entities_found }
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'ApiIngest#publish_to_apollo')
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
                access_scope:    'private',
                context:         { entity_name: entity[:name], entity_type: entity[:type],
                                   confidence: entity[:confidence], extracted_from: person_name }
              )
            end

            { success: true, count: result[:entities].length }
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: 'ApiIngest#extract_and_ingest_entities',
                             person_name: person_name)
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

          def members_cache_ttl
            return @members_cache_ttl if defined?(@members_cache_ttl)

            @members_cache_ttl = if respond_to?(:settings, true) && settings.respond_to?(:dig)
                                   settings.dig(:cache, :members_ttl) || 86_400
                                 else
                                   86_400
                                 end
          end

          def error_result(message)
            { result: { stored: 0, skipped: 0, error: message } }
          end
        end
      end
    end
  end
end
