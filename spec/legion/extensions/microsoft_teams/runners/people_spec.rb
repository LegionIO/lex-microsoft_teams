# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::People do
  let(:runner) { Object.new.extend(described_class) }
  let(:conn) { instance_double(Faraday::Connection) }
  let(:response) { instance_double(Faraday::Response) }

  before do
    allow(runner).to receive(:graph_connection).and_return(conn)
  end

  describe '#get_profile' do
    let(:profile_body) do
      {
        'displayName' => 'Jane Doe',
        'mail' => 'jane.doe@example.com',
        'jobTitle' => 'Senior Engineer',
        'department' => 'Platform Engineering',
        'officeLocation' => 'Minneapolis'
      }
    end

    before do
      allow(conn).to receive(:get).with('me').and_return(response)
      allow(response).to receive(:body).and_return(profile_body)
    end

    it 'returns user profile data' do
      result = runner.get_profile
      expect(result[:result]).to eq(profile_body)
    end

    it 'uses user_path for non-me user_id' do
      allow(conn).to receive(:get).with('users/abc-123').and_return(response)
      result = runner.get_profile(user_id: 'abc-123')
      expect(result[:result]).to eq(profile_body)
    end
  end

  describe '#list_people' do
    let(:people_body) do
      {
        'value' => [
          { 'displayName' => 'Jane Doe', 'scoredEmailAddresses' => [{ 'relevanceScore' => 8.0 }] },
          { 'displayName' => 'Bob Smith', 'scoredEmailAddresses' => [{ 'relevanceScore' => 5.0 }] }
        ]
      }
    end

    before do
      allow(conn).to receive(:get).with('me/people', { '$top' => 25 }).and_return(response)
      allow(response).to receive(:body).and_return(people_body)
    end

    it 'returns ranked people list' do
      result = runner.list_people
      expect(result[:result]['value'].length).to eq(2)
    end

    it 'respects the top parameter' do
      allow(conn).to receive(:get).with('me/people', { '$top' => 10 }).and_return(response)
      runner.list_people(top: 10)
    end

    it 'uses user_path for non-me user_id' do
      allow(conn).to receive(:get).with('users/abc-123/people', { '$top' => 25 }).and_return(response)
      runner.list_people(user_id: 'abc-123')
    end
  end
end
