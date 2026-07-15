# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        module GraphCache
          include Legion::Cache::Helper if defined?(Legion::Cache::Helper)

          def graph_cache_ttl
            settings = teams_extension_settings
            settings.dig(:cache, :graph_ttl) || 300
          end

          def cached_graph_get(conn:, path:, params: {}, ttl: nil, shared: false)
            effective_ttl = ttl || graph_cache_ttl
            key = graph_cache_key(path: path, params: params, shared: shared)

            cache_fetch(key, ttl: effective_ttl) do
              resp = conn.get(path, params)
              resp.body
            end
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'GraphCache#cached_graph_get', path: path)
            conn.get(path, params).body
          end

          def graph_user_key
            return @graph_user_key if defined?(@graph_user_key)

            @graph_user_key = (Legion::Identity::Process.id if defined?(Legion::Identity::Process) && Legion::Identity::Process.resolved?)
          end

          def invalidate_graph_cache(path:, params: {}, shared: false)
            key = graph_cache_key(path: path, params: params, shared: shared)
            cache_delete(key)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'GraphCache#invalidate_graph_cache')
          end

          private

          def graph_cache_key(path:, params: {}, shared: false)
            scope = if shared
                      'shared'
                    else
                      graph_user_key || 'anon'
                    end
            param_str = params.empty? ? '' : ":#{params.sort.map { |k, v| "#{k}=#{v}" }.join('&')}"
            "graph:#{scope}:#{path}#{param_str}"
          end

          def teams_extension_settings
            return {} unless defined?(Legion::Settings)

            Legion::Settings[:microsoft_teams] || {}
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'GraphCache#teams_extension_settings')
            {}
          end
        end
      end
    end
  end
end
