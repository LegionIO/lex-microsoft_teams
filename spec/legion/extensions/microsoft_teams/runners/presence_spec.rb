# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Presence do
  let(:runner) { Object.new.extend(described_class) }
  let(:mock_client) { double('client') } # rubocop:disable RSpec/VerifiedDoubles

  before do
    allow(runner).to receive(:client).and_return(mock_client)
  end

  describe '#get_presence' do
    it 'returns presence data for a user' do
      allow(mock_client).to receive(:get)
        .with('/users/user-123/presence')
        .and_return({ 'availability' => 'Available', 'activity' => 'Available' })

      result = runner.get_presence(user_id: 'user-123')
      expect(result[:availability]).to eq('Available')
      expect(result[:activity]).to eq('Available')
      expect(result[:fetched_at]).to be_a(Time)
    end

    it 'returns Offline when API call fails' do
      allow(mock_client).to receive(:get).and_raise(StandardError, 'connection timeout')

      result = runner.get_presence(user_id: 'user-123')
      expect(result[:availability]).to eq('Offline')
      expect(result[:error]).to eq('connection timeout')
    end

    it 'handles symbol-keyed responses' do
      allow(mock_client).to receive(:get)
        .and_return({ availability: 'Busy', activity: 'InAMeeting' })

      result = runner.get_presence(user_id: 'user-123')
      expect(result[:availability]).to eq('Busy')
      expect(result[:activity]).to eq('InAMeeting')
    end
  end
end
