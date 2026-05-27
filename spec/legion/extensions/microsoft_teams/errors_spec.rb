# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/microsoft_teams/errors'

RSpec.describe Legion::Extensions::MicrosoftTeams::Errors::Throttled do
  it 'is a StandardError' do
    expect(described_class.ancestors).to include(StandardError)
  end

  it 'exposes status, retry_after, request and attempts' do
    error = described_class.new(status: 429, retry_after: 12.5, request: '/me/chats', attempts: 3)

    expect(error.status).to eq(429)
    expect(error.retry_after).to eq(12.5)
    expect(error.request).to eq('/me/chats')
    expect(error.attempts).to eq(3)
  end

  it 'coerces retry_after to Float' do
    error = described_class.new(status: 429, retry_after: '7')

    expect(error.retry_after).to eq(7.0)
  end

  it 'includes status and retry_after in the message' do
    error = described_class.new(status: 429, retry_after: 5.0, request: '/me/chats', attempts: 2)

    expect(error.message).to include('429')
    expect(error.message).to include('5.00')
    expect(error.message).to include('/me/chats')
    expect(error.message).to include('2 attempt')
  end

  it 'omits attempts from the message when not provided' do
    error = described_class.new(status: 429, retry_after: 1.0)

    expect(error.message).not_to include('attempt(s)')
  end
end
