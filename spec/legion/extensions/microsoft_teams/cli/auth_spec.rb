# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/microsoft_teams/cli/auth'

RSpec.describe Legion::Extensions::MicrosoftTeams::CLI::Auth do
  let(:cli) { described_class.new }

  describe '#login' do
    it 'instantiates BrowserAuth and calls authenticate' do
      browser_auth = double('browser_auth')
      allow(Legion::Extensions::MicrosoftTeams::Helpers::BrowserAuth).to receive(:new).and_return(browser_auth)
      expect(browser_auth).to receive(:authenticate).and_return({ access_token: 'tok' })
      allow(cli).to receive(:store_token)
      allow(cli).to receive(:puts)
      cli.login(tenant_id: 'tid', client_id: 'cid')
    end
  end

  describe '#status' do
    it 'reports unauthenticated when no token exists' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.expand_path('~/.legionio/tokens/microsoft_teams.json')).and_return(false)
      expect { cli.status }.to output(/not authenticated/i).to_stdout
    end
  end

  describe '.cli_alias' do
    it 'returns teams' do
      expect(described_class.cli_alias).to eq('teams')
    end
  end

  describe '.descriptions' do
    it 'returns a hash of command descriptions' do
      expect(described_class.descriptions).to include(:login, :status)
    end
  end
end
