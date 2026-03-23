# frozen_string_literal: true

require 'bundler/setup'
require 'legion/logging'

# Define Helpers::Lex using the real Legion::Logging::Helper so guarded
# includes resolve in tests and all classes get a working `log` method.
module Legion
  module Extensions
    module Helpers
      module Lex
        include Legion::Logging::Helper
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
