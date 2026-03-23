# frozen_string_literal: true

require 'bundler/setup'
require 'logger'

# Stub Legion::Extensions::Helpers::Lex so the guarded includes resolve in tests.
# Provides a null-ish `log` method matching the interface from the real Helpers::Logger.
module Legion
  module Extensions
    module Helpers
      module Lex
        def log
          @log ||= ::Logger.new(File::NULL)
        end
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

require 'legion/extensions/microsoft_teams'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
