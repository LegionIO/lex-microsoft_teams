# frozen_string_literal: true

require 'spec_helper'

module Legion
  module Transport
    class Message
      def initialize(**); end
    end
  end
end

require 'legion/extensions/microsoft_teams/transport/exchanges/messages'
require 'legion/extensions/microsoft_teams/transport/messages/teams_message'

RSpec.describe Legion::Extensions::MicrosoftTeams::Transport::Messages::TeamsMessage do
  subject(:message) { described_class.new }

  it 'routes to teams.messages.process' do
    expect(message.routing_key).to eq('teams.messages.process')
  end
end
