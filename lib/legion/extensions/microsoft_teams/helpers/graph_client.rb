# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        module GraphClient
          class GraphError < StandardError; end

          def graph_get(path, token:, params: {})
            connection = graph_connection(token: token)
            response   = connection.get(path, params)
            handle_graph_response(response, path)
          end

          def graph_paginate(path, token:, params: {}, max_pages: 10)
            results   = []
            next_link = nil
            page      = 0

            loop do
              current_path = next_link || path
              data         = graph_get(current_path, token: token, params: page.zero? ? params : {})
              break if data.nil?

              items = data['value'] || data[:value]
              results.concat(Array(items)) if items

              next_link = data['@odata.nextLink'] || data[:'@odata.nextLink']
              page     += 1
              break if next_link.nil? || page >= max_pages
            end

            results
          end

          def graph_post(path, token:, body: {})
            connection = graph_connection(token: token)
            response   = connection.post(path) do |req|
              req.body = body
            end
            handle_graph_response(response, path)
          end

          private

          def handle_graph_response(response, path)
            error_message =
              if response.body.respond_to?(:dig)
                response.body.dig('error', 'message') ||
                  response.body.dig(:error, :message)
              end

            case response.status
            when 200, 201
              response.body
            when 204, 404
              nil
            when 401
              detail = error_message || 'Access token is missing, expired, or invalid.'
              raise GraphError, "Graph API 401 Unauthorized on #{path}: #{detail}"
            when 403
              detail = error_message || 'Caller does not have sufficient permissions to perform this action.'
              raise GraphError, "Graph API 403 Forbidden on #{path}: #{detail}"
            else
              base_message = "Graph API #{response.status} on #{path}"
              base_message = "#{base_message}: #{error_message}" if error_message
              raise GraphError, base_message
            end
          end
        end
      end
    end
  end
end
