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

require 'legion/extensions/microsoft_teams'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
