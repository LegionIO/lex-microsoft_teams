# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'legion/extensions/microsoft_teams/helpers/client'

module Legion
  module Extensions
    module MicrosoftTeams
      module Runners
        module Loop
          include Legion::Extensions::MicrosoftTeams::Helpers::Client

          # Creates a new .loop file in the user's OneDrive via the Graph API.
          # The Fluid Framework collaborative session is initialized by Teams on first open.
          # Returns the drive item metadata including +webUrl+, which can be passed to
          # +post_loop_to_chat+ or +post_loop_to_channel+.
          #
          # @param filename     [String] Name of the file (e.g. "incident-status" or "incident-status.loop")
          # @param folder_path  [String] OneDrive folder path relative to root (default: root)
          # @param user_id      [String] Graph user ID or 'me' (default: 'me')
          def create_loop_file(filename:, folder_path: nil, user_id: 'me', **)
            filename = "#{filename}.loop" unless filename.end_with?('.loop')

            path = if folder_path.nil? || folder_path.empty?
                     "users/#{user_id}/drive/root:/#{filename}:/content"
                   else
                     "users/#{user_id}/drive/root:/#{folder_path}/#{filename}:/content"
                   end

            response = graph_connection(**).put(path, '', 'Content-Type' => 'application/octet-stream')
            { result: response.body }
          end

          # Builds the fluidEmbedCard attachment array required to embed a Loop component
          # in a Teams message. Pass the resulting array as +attachments:+ to
          # +send_chat_message+ / +send_channel_message+, or use the convenience methods
          # +post_loop_to_chat+ and +post_loop_to_channel+.
          #
          # @param component_url [String] SharePoint/OneDrive URL of the .loop file
          #                               (the +webUrl+ from +create_loop_file+)
          # @param source_type   [String] 'Compose' (default) or 'Loop'
          def loop_attachment(component_url:, source_type: 'Compose', **)
            attachment_id = SecureRandom.hex(16)
            {
              result: [
                {
                  id:          attachment_id,
                  contentType: 'application/vnd.microsoft.card.fluidEmbedCard',
                  contentUrl:  nil,
                  content:     JSON.generate({ componentUrl: component_url, sourceType: source_type }),
                  teamsAppId:  'FluidEmbedCard'
                },
                {
                  id:          'placeholderCard',
                  contentType: 'application/vnd.microsoft.card.codesnippet',
                  content:     '{}',
                  teamsAppId:  'FLUID_PLACEHOLDER_CARD'
                }
              ]
            }
          end

          # Posts a message into a Teams chat thread with a Loop component embedded inline.
          #
          # @param chat_id       [String] Teams chat thread ID (e.g. 19:...@thread.v2)
          # @param component_url [String] SharePoint/OneDrive URL of the .loop file
          # @param body_text     [String] Optional plain-text preamble shown above the component
          def post_loop_to_chat(chat_id:, component_url:, body_text: '', **)
            attachments = loop_attachment(component_url: component_url, **)[:result]
            content     = body_text.empty? ? '<p></p>' : "<p>#{body_text}</p>"
            payload     = { body: { contentType: 'html', content: content }, attachments: attachments }
            response    = graph_connection(**).post("chats/#{chat_id}/messages", payload)
            { result: response.body }
          end

          # Posts a message into a Teams channel thread with a Loop component embedded inline.
          #
          # @param team_id       [String] Teams team ID
          # @param channel_id    [String] Teams channel ID
          # @param component_url [String] SharePoint/OneDrive URL of the .loop file
          # @param body_text     [String] Optional plain-text preamble shown above the component
          # @param subject       [String] Optional thread subject line
          def post_loop_to_channel(team_id:, channel_id:, component_url:, body_text: '', subject: nil, **)
            attachments = loop_attachment(component_url: component_url, **)[:result]
            content     = body_text.empty? ? '<p></p>' : "<p>#{body_text}</p>"
            payload     = { body: { contentType: 'html', content: content }, attachments: attachments }
            payload[:subject] = subject if subject
            response = graph_connection(**).post("teams/#{team_id}/channels/#{channel_id}/messages", payload)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
