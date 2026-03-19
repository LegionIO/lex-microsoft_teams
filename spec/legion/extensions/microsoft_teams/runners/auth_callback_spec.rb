# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Legion::Extensions::MicrosoftTeams::Runners::Auth#auth_callback' do
  let(:runner) { Object.new.extend(Legion::Extensions::MicrosoftTeams::Runners::Auth) }

  before do
    allow(runner).to receive(:oauth_connection)
  end

  describe '#auth_callback' do
    context 'with valid code and state' do
      it 'returns success with HTML response' do
        result = runner.auth_callback(code: 'auth-code', state: 'csrf-state')
        expect(result[:result][:authenticated]).to be true
        expect(result[:response][:status]).to eq(200)
        expect(result[:response][:content_type]).to eq('text/html')
        expect(result[:response][:body]).to include('Authentication complete')
      end

      it 'passes code and state in result' do
        result = runner.auth_callback(code: 'auth-code', state: 'csrf-state')
        expect(result[:result][:code]).to eq('auth-code')
        expect(result[:result][:state]).to eq('csrf-state')
      end

      it 'emits oauth callback event when Legion::Events is available' do
        stub_const('Legion::Events', double)
        allow(Legion::Events).to receive(:emit)

        runner.auth_callback(code: 'auth-code', state: 'csrf-state')
        expect(Legion::Events).to have_received(:emit).with(
          'microsoft_teams.oauth.callback', code: 'auth-code', state: 'csrf-state'
        )
      end
    end

    context 'with missing code' do
      it 'returns 400 with error HTML' do
        result = runner.auth_callback(state: 'csrf-state')
        expect(result[:result][:error]).to eq('missing_params')
        expect(result[:response][:status]).to eq(400)
        expect(result[:response][:body]).to include('Missing code or state')
      end
    end

    context 'with missing state' do
      it 'returns 400 with error HTML' do
        result = runner.auth_callback(code: 'auth-code')
        expect(result[:result][:error]).to eq('missing_params')
        expect(result[:response][:status]).to eq(400)
      end
    end

    context 'with both missing' do
      it 'returns 400 with error HTML' do
        result = runner.auth_callback
        expect(result[:result][:error]).to eq('missing_params')
        expect(result[:response][:status]).to eq(400)
      end
    end
  end
end
