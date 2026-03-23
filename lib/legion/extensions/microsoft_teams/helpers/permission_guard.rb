# frozen_string_literal: true

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        module PermissionGuard
          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)

          BACKOFF_SCHEDULE = [60, 300, 1800, 7200, 28_800].freeze

          def permission_denied?(endpoint)
            denial = permission_denials[endpoint]
            return false unless denial

            Time.now.utc < denial[:retry_after]
          end

          def record_denial(endpoint, error_message)
            denial = permission_denials[endpoint] || { count: 0 }
            denial[:count] += 1
            backoff = BACKOFF_SCHEDULE.fetch(denial[:count] - 1, BACKOFF_SCHEDULE.last)
            denial[:retry_after] = Time.now.utc + backoff
            permission_denials[endpoint] = denial
            log.warn("Graph API permission denied for #{endpoint}: #{error_message}. " \
                     "Retry in #{backoff}s (attempt #{denial[:count]})")
          end

          def denial_info(endpoint)
            permission_denials[endpoint]
          end

          def reset_denials!
            @permission_denials = {}
          end

          def guarded_request(endpoint)
            return { skipped: true, endpoint: endpoint, reason: :permission_denied } if permission_denied?(endpoint)

            result = yield
            if result.is_a?(Hash) && result[:status] == 403
              msg = result.dig(:result, 'error', 'message') || 'Unknown'
              record_denial(endpoint, msg)
            end
            result
          end

          private

          def permission_denials
            @permission_denials ||= {}
          end
        end
      end
    end
  end
end
