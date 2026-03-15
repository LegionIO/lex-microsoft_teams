# frozen_string_literal: true

require 'spec_helper'

module Legion
  module Transport
    class Exchange
      def initialize(**); end
    end
  end
end

require 'legion/extensions/microsoft_teams/transport/exchanges/messages'

RSpec.describe Legion::Extensions::MicrosoftTeams::Transport::Exchanges::Messages do
  subject(:exchange) { described_class.new }

  it 'has exchange name teams.messages' do
    expect(exchange.exchange_name).to eq('teams.messages')
  end
end
