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
              items        = data['value'] || data[:value]
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
            case response.status
            when 200, 201
              response.body
            when 404
              nil
            else
              raise GraphError, "Graph API #{response.status} on #{path}"
            end
          end
        end
      end
    end
  end
end
