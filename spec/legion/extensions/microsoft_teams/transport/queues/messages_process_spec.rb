# frozen_string_literal: true

require 'spec_helper'

module Legion
  module Transport
    class Queue
      def initialize(**); end
    end
  end
end

require 'legion/extensions/microsoft_teams/transport/queues/messages_process'

RSpec.describe Legion::Extensions::MicrosoftTeams::Transport::Queues::MessagesProcess do
  subject(:queue) { described_class.new }

  it 'has queue name teams.messages.process' do
    expect(queue.queue_name).to eq('teams.messages.process')
  end

  it 'is not auto-deleted' do
    expect(queue.queue_options[:auto_delete]).to be false
  end
end
