# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth do
  let(:auth_runner) { Object.new.extend(Legion::Extensions::MicrosoftTeams::Runners::Auth) }
  let(:browser_auth) do
    described_class.new(
      tenant_id: 'test-tenant',
      client_id: 'app-id',
      scopes:    'OnlineMeetings.Read offline_access',
      auth:      auth_runner
    )
  end

  describe '#generate_pkce' do
    it 'returns a verifier and challenge pair' do
      verifier, challenge = browser_auth.generate_pkce
      expect(verifier).to be_a(String)
      expect(verifier.length).to be >= 43
      expect(challenge).to be_a(String)
      expect(challenge).not_to eq(verifier)
    end

    it 'generates a valid S256 challenge' do
      require 'digest'
      require 'base64'
      verifier, challenge = browser_auth.generate_pkce
      expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      expect(challenge).to eq(expected)
    end
  end

  describe '#gui_available?' do
    it 'returns true on macOS' do
      allow(browser_auth).to receive(:host_os).and_return('darwin22')
      expect(browser_auth.gui_available?).to be true
    end

    it 'returns false on Linux without DISPLAY' do
      allow(browser_auth).to receive(:host_os).and_return('linux-gnu')
      allow(ENV).to receive(:[]).with('DISPLAY').and_return(nil)
      allow(ENV).to receive(:[]).with('WAYLAND_DISPLAY').and_return(nil)
      expect(browser_auth.gui_available?).to be false
    end

    it 'returns true on Linux with DISPLAY' do
      allow(browser_auth).to receive(:host_os).and_return('linux-gnu')
      allow(ENV).to receive(:[]).with('DISPLAY').and_return(':0')
      expect(browser_auth.gui_available?).to be true
    end
  end

  describe '#open_browser' do
    it 'calls system open on macOS' do
      allow(browser_auth).to receive(:host_os).and_return('darwin22')
      allow(browser_auth).to receive(:system).and_return(true)
      expect(browser_auth.open_browser('https://example.com')).to be true
    end

    it 'returns false for unknown OS' do
      allow(browser_auth).to receive(:host_os).and_return('unknown-os')
      expect(browser_auth.open_browser('https://example.com')).to be false
    end
  end

  describe '#authenticate' do
    it 'uses browser flow when GUI is available' do
      allow(browser_auth).to receive(:gui_available?).and_return(true)
      allow(browser_auth).to receive(:authenticate_browser).and_return({ result: { 'access_token' => 'tok' } })
      result = browser_auth.authenticate
      expect(result[:result]['access_token']).to eq('tok')
    end

    it 'uses device code flow when headless' do
      allow(browser_auth).to receive(:gui_available?).and_return(false)
      allow(browser_auth).to receive(:authenticate_device_code).and_return({ result: { 'access_token' => 'tok' } })
      result = browser_auth.authenticate
      expect(result[:result]['access_token']).to eq('tok')
    end
  end
end
