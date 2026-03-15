# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Presence do
  let(:runner) { Object.new.extend(described_class) }
  let(:faraday_response) { instance_double(Faraday::Response, body: response_body) }
  let(:conn) { instance_double(Faraday::Connection, get: faraday_response) }

  before do
    allow(runner).to receive(:graph_connection).and_return(conn)
  end

  describe '#get_presence' do
    let(:response_body) { { 'availability' => 'Available', 'activity' => 'Available' } }

    it 'returns presence data for a user' do
      result = runner.get_presence(user_id: 'user-123')
      expect(result[:availability]).to eq('Available')
      expect(result[:activity]).to eq('Available')
      expect(result[:fetched_at]).to be_a(Time)
    end

    it 'calls the correct graph endpoint' do
      runner.get_presence(user_id: 'user-123')
      expect(conn).to have_received(:get).with('/users/user-123/presence')
    end

    it 'returns Offline when API call fails' do
      allow(conn).to receive(:get).and_raise(StandardError, 'connection timeout')
      result = runner.get_presence(user_id: 'user-123')
      expect(result[:availability]).to eq('Offline')
      expect(result[:error]).to eq('connection timeout')
    end
  end
end
