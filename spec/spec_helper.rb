# frozen_string_literal: true

require 'bundler/setup'
require 'legion/logging'
require 'legion/settings'
require 'legion/cache/helper'
require 'legion/crypt/helper'
require 'legion/data/helper'
require 'legion/json/helper'
require 'legion/transport'

# Define Helpers::Lex using the real helpers from sub-gems so guarded
# includes resolve in tests and all classes get working log, settings,
# cache, and vault methods.
module Legion
  module Extensions
    module Helpers
      module Lex
        include Legion::Logging::Helper
        include Legion::Settings::Helper
        include Legion::Cache::Helper
        include Legion::Crypt::Helper
        include Legion::Data::Helper
        include Legion::JSON::Helper
        include Legion::Transport::Helper
      end
    end

    module Actors
      class Every
        include Helpers::Lex
      end

      class Once
        include Helpers::Lex
      end
    end
  end
end

# Stub the absorbers framework base classes so the absorber can be loaded
# without the full legionio gem in the test environment.
unless defined?(Legion::Extensions::Absorbers)
  require 'uri'

  module Legion
    module Extensions
      module Absorbers
        module Matchers
          class Base
            def self.match?(_pattern, _input)
              false
            end
          end

          class Url < Base
            def self.type = :url

            def self.match?(pattern, input)
              str = input.to_s.strip
              str = "https://#{str}" unless str.match?(%r{\A\w+://})
              uri = URI.parse(str)
              return false unless uri.is_a?(URI::HTTP) && uri.host

              clean = pattern.sub(%r{\A\w+://}, '')
              parts = clean.split('/', 2)
              host_pattern = parts[0]
              path_pattern = parts[1] || '**'

              host_regex = Regexp.new(
                "\\A#{Regexp.escape(host_pattern).gsub('\\*', '[^.]+')}\\z",
                Regexp::IGNORECASE
              )
              return false unless host_regex.match?(uri.host)

              path = uri.path.to_s.sub(%r{\A/}, '')
              escaped = Regexp.escape(path_pattern)
                              .gsub('\\*\\*', '__.DS__.').gsub('\\*', '[^/]*').gsub('__.DS__.', '.*')
              Regexp.new("\\A#{escaped}\\z").match?(path)
            rescue URI::InvalidURIError
              false
            end
          end
        end

        class Base
          attr_accessor :job_id, :runners

          class << self
            def pattern(type, value, priority: 100)
              @patterns ||= []
              @patterns << { type: type, value: value, priority: priority }
            end

            def patterns
              @patterns || []
            end

            def description(text = nil)
              text ? @description = text : @description
            end
          end

          def handle(url: nil, content: nil, metadata: {}, context: {})
            raise NotImplementedError, "#{self.class.name} must implement #handle"
          end

          def absorb_to_knowledge(content:, tags: [], scope: :global, **opts); end
          def absorb_raw(content:, tags: [], scope: :global, **); end

          def report_progress(message:, percent: nil)
            return unless job_id
            return unless defined?(Legion::Logging)

            Legion::Logging.info("absorb[#{job_id}] #{"#{percent}% " if percent}#{message}")
          end
        end
      end
    end
  end
end

require 'legion/extensions/microsoft_teams'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
