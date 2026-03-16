# frozen_string_literal: true

require 'json'
require 'legion/extensions/microsoft_teams/helpers/client'
require_relative '../helpers/session_manager'
require_relative '../helpers/subscription_registry'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Bot
          include Legion::Extensions::MicrosoftTeams::Helpers::Client
          include Legion::Extensions::MicrosoftTeams::Helpers::PromptResolver

          def send_activity(service_url:, conversation_id:, activity:, **)
            conn = bot_connection(service_url: service_url, **)
            response = conn.post("/v3/conversations/#{conversation_id}/activities", activity)
            { result: response.body }
          end

          def reply_to_activity(service_url:, conversation_id:, activity_id:, text: nil,
                                attachments: [], content_type: 'message', **)
            activity = { type: content_type, text: text }
            activity[:attachments] = attachments unless attachments.empty?
            conn = bot_connection(service_url: service_url, **)
            response = conn.post(
              "/v3/conversations/#{conversation_id}/activities/#{activity_id}", activity
            )
            { result: response.body }
          end

          def send_text(service_url:, conversation_id:, text:, **)
            send_activity(
              service_url:     service_url,
              conversation_id: conversation_id,
              activity:        { type: 'message', text: text },
              **
            )
          end

          def send_card(service_url:, conversation_id:, card:, **)
            attachment = {
              contentType: 'application/vnd.microsoft.card.adaptive',
              contentUrl:  nil,
              content:     card
            }
            send_activity(
              service_url:     service_url,
              conversation_id: conversation_id,
              activity:        { type: 'message', attachments: [attachment] },
              **
            )
          end

          def create_conversation(service_url:, bot_id:, user_id:, tenant_id: nil, **)
            payload = {
              bot:     { id: bot_id },
              members: [{ id: user_id }],
              isGroup: false
            }
            payload[:tenantId] = tenant_id if tenant_id
            conn = bot_connection(service_url: service_url, **)
            response = conn.post('/v3/conversations', payload)
            { result: response.body }
          end

          def get_conversation_members(service_url:, conversation_id:, **)
            conn = bot_connection(service_url: service_url, **)
            response = conn.get("/v3/conversations/#{conversation_id}/members")
            { result: response.body }
          end

          def handle_message(chat_id:, conversation_id:, text:, owner_id:, mode: :direct, **opts)
            command_result = handle_command(text: text, owner_id: owner_id, chat_id: chat_id, **opts)
            if command_result
              reply_text = command_result[:message]
              send_reply(
                chat_id: chat_id, conversation_id: conversation_id,
                activity_id: opts[:activity_id], service_url: opts[:service_url],
                text: reply_text, token: opts[:token]
              )
              return { result: command_result }
            end

            session = session_manager.get_or_create(
              conversation_id: conversation_id, owner_id: owner_id, mode: mode
            )
            session_manager.add_message(conversation_id: conversation_id, role: :user, content: text)

            response_text = generate_response(text: text, session: session)

            reply_result = send_reply(
              chat_id:         chat_id,
              conversation_id: conversation_id,
              activity_id:     opts[:activity_id],
              service_url:     opts[:service_url],
              text:            response_text,
              token:           opts[:token]
            )

            session_manager.add_message(conversation_id: conversation_id, role: :assistant, content: response_text)
            session_manager.touch(conversation_id: conversation_id)
            session_manager.persist(conversation_id: conversation_id) if session_manager.should_flush?(conversation_id: conversation_id)

            { result: reply_result }
          end

          def observe_message(chat_id:, owner_id:, text:, from:, peer_name:, timestamp: nil, **)
            return { result: :skipped, reason: :observe_disabled } unless observe_enabled?

            extraction = extract_from_message(text: text, from: from, peer_name: peer_name)

            store_observation(
              chat_id: chat_id, owner_id: owner_id, text: text,
              from: from, peer_name: peer_name, extraction: extraction,
              timestamp: timestamp
            )

            if extraction && extraction[:action_items]&.any? && notify_enabled?(owner_id: owner_id, chat_id: chat_id)
              notify_owner(owner_id: owner_id, extraction: extraction, peer_name: peer_name)
            end

            { result: extraction || { raw_text: text } }
          end

          def session_manager
            @session_manager ||= Legion::Extensions::MicrosoftTeams::Helpers::SessionManager.new
          end

          def subscription_registry
            @subscription_registry ||= Legion::Extensions::MicrosoftTeams::Helpers::SubscriptionRegistry.new
          end

          def handle_command(text:, owner_id:, chat_id:, **)
            stripped = text.strip

            case stripped
            when /\Awatch\s+(.+)/i
              cmd_watch(name: ::Regexp.last_match(1).strip, owner_id: owner_id, chat_id: chat_id, **)
            when /\A(?:stop\s+watching|unwatch)\s+(.+)/i
              cmd_unwatch(name: ::Regexp.last_match(1).strip, owner_id: owner_id)
            when /\A(?:watching|list|subscriptions)\z/i
              cmd_list(owner_id: owner_id)
            when /\Apause\s+(.+)/i
              cmd_pause(name: ::Regexp.last_match(1).strip, owner_id: owner_id)
            when /\Aresume\s+(.+)/i
              cmd_resume(name: ::Regexp.last_match(1).strip, owner_id: owner_id)
            end
          end

          private

          def generate_response(text:, session:)
            return llm_respond(text: text, session: session) if llm_available?

            "Echo: #{text}"
          end

          def llm_respond(text:, session:)
            config = session[:llm_config] || {}
            response = llm_chat(
              text,
              instructions: session[:system_prompt],
              model:        config[:model],
              intent:       config[:intent]
            )
            response.content
          rescue StandardError => e
            log_error("LLM call failed: #{e.message}")
            'I encountered an error processing your message. Please try again.'
          end

          def llm_available?
            defined?(Legion::LLM) && Legion::LLM.respond_to?(:chat)
          end

          def send_reply(chat_id:, conversation_id:, activity_id:, service_url:, text:, token:)
            if service_url && activity_id
              reply_to_activity(
                service_url:     service_url, conversation_id: conversation_id,
                activity_id:     activity_id, text: text, token: token
              )
            else
              send_chat_message_via_graph(chat_id: chat_id, text: text, token: token)
            end
          end

          def send_chat_message_via_graph(chat_id:, text:, token: nil, **)
            conn = graph_connection(token: token)
            response = conn.post("/chats/#{chat_id}/messages", { body: { contentType: 'text', content: text } })
            { result: response.body }
          end

          def log_error(msg)
            Legion::Logging.error(msg) if defined?(Legion::Logging)
          end

          def observe_enabled?
            return false unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :bot, :observe, :enabled) == true
          end

          def notify_enabled?(**_kwargs)
            return false unless defined?(Legion::Settings)

            Legion::Settings.dig(:microsoft_teams, :bot, :observe, :notify) == true
          end

          def extract_from_message(text:, from:, peer_name:)
            return nil unless llm_available?

            prompt = resolve_prompt(mode: :observe, conversation_id: nil)
            context = "#{from[:name] || peer_name} said: #{text}"

            response = llm_chat(context, instructions: prompt)
            parse_extraction(response.content)
          rescue StandardError => e
            log_error("Observation extraction failed: #{e.message}")
            nil
          end

          def parse_extraction(content)
            parsed = ::JSON.parse(content, symbolize_names: true)
            parsed if parsed.is_a?(Hash)
          rescue ::JSON::ParserError
            { summary: content }
          end

          def store_observation(chat_id:, owner_id:, text:, from:, peer_name:, extraction:, timestamp:)
            return unless memory_available?

            memory_runner.store_trace(
              type:            :episodic,
              content_payload: {
                type:       :observed_message,
                chat_id:    chat_id,
                owner_id:   owner_id,
                from:       from,
                peer_name:  peer_name,
                text:       text,
                extraction: extraction,
                timestamp:  timestamp
              }.to_s,
              domain_tags:     ['teams', 'observed', "peer:#{peer_name}", "chat:#{chat_id}"],
              origin:          :direct_experience,
              confidence:      0.6
            )
          rescue StandardError => e
            log_error("Observation store failed: #{e.message}")
          end

          def notify_owner(owner_id:, peer_name:, extraction: nil) # rubocop:disable Lint/UnusedMethodArgument
            log_info("Would notify #{owner_id} about action items from #{peer_name}")
          end

          def memory_available?
            defined?(Legion::Extensions::Memory::Runners::Traces)
          end

          def memory_runner
            @memory_runner ||= Object.new.extend(Legion::Extensions::Memory::Runners::Traces)
          end

          def log_info(msg)
            Legion::Logging.info(msg) if defined?(Legion::Logging)
          end

          def cmd_watch(name:, owner_id:, chat_id: nil, token: nil, **) # rubocop:disable Lint/UnusedMethodArgument
            target_chat = find_chat_with_person(name: name, token: token)
            return { command: :watch, success: false, message: "Could not find a chat with '#{name}'." } unless target_chat

            subscription_registry.subscribe(
              owner_id: owner_id, chat_id: target_chat[:id], peer_name: name
            )
            { command: :watch, success: true,
              message: "Now watching your conversation with #{name}." }
          end

          def cmd_unwatch(name:, owner_id:)
            sub = subscription_registry.find_by_peer_name(owner_id: owner_id, peer_name: name)
            return { command: :unwatch, success: false, message: "No subscription found for '#{name}'." } unless sub

            subscription_registry.unsubscribe(owner_id: owner_id, chat_id: sub[:chat_id])
            { command: :unwatch, success: true,
              message: "Stopped watching #{name}." }
          end

          def cmd_list(owner_id:)
            subs = subscription_registry.list(owner_id: owner_id)
            return { command: :list, success: true, message: 'No active subscriptions.' } if subs.empty?

            lines = subs.map do |s|
              status = s[:enabled] ? 'active' : 'paused'
              "- #{s[:peer_name]} (#{status})"
            end
            { command: :list, success: true,
              message: "Subscriptions:\n#{lines.join("\n")}" }
          end

          def cmd_pause(name:, owner_id:)
            sub = subscription_registry.find_by_peer_name(owner_id: owner_id, peer_name: name)
            return { command: :pause, success: false, message: "No subscription found for '#{name}'." } unless sub

            subscription_registry.pause(owner_id: owner_id, chat_id: sub[:chat_id])
            { command: :pause, success: true, message: "Paused watching #{name}." }
          end

          def cmd_resume(name:, owner_id:)
            sub = subscription_registry.find_by_peer_name(owner_id: owner_id, peer_name: name)
            return { command: :resume, success: false, message: "No subscription found for '#{name}'." } unless sub

            subscription_registry.resume(owner_id: owner_id, chat_id: sub[:chat_id])
            { command: :resume, success: true, message: "Resumed watching #{name}." }
          end

          def find_chat_with_person(name:, token: nil)
            conn = graph_connection(token: token)
            response = conn.get('/me/chats', { '$filter' => "chatType eq 'oneOnOne'", '$top' => 50 })
            chats = response.body&.dig('value') || []

            chats.each do |chat|
              members_resp = conn.get("/chats/#{chat['id']}/members")
              members = members_resp.body&.dig('value') || members_resp.body || []
              return { id: chat['id'] } if members.any? { |m| m['displayName']&.downcase&.include?(name.downcase) }
            end
            nil
          rescue StandardError => e
            log_error("find_chat_with_person failed: #{e.message}")
            nil
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
