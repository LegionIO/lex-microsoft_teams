# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/microsoft_teams/errors'

RSpec.describe Legion::Extensions::MicrosoftTeams::Errors::Throttled do
  it 'is a StandardError so existing rescue chains catch it' do
    expect(described_class.ancestors).to include(StandardError)
  end

  describe 'attribute exposure' do
    it 'exposes status, retry_after, request and attempts' do
      error = described_class.new(status: 429, retry_after: 12.5, request: '/me/chats', attempts: 3)

      expect(error.status).to eq(429)
      expect(error.retry_after).to eq(12.5)
      expect(error.request).to eq('/me/chats')
      expect(error.attempts).to eq(3)
    end

    it 'coerces retry_after from a numeric string' do
      expect(described_class.new(status: 429, retry_after: '7').retry_after).to eq(7.0)
    end

    it 'clamps negative retry_after to zero' do
      expect(described_class.new(status: 429, retry_after: -3.0).retry_after).to eq(0.0)
    end

    it 'coerces attempts to Integer when provided' do
      expect(described_class.new(status: 429, retry_after: 1, attempts: '5').attempts).to eq(5)
    end
  end

  describe 'nullable retry_after' do
    it 'accepts nil retry_after to express "no server guidance"' do
      error = described_class.new(status: 429, retry_after: nil)

      expect(error.retry_after).to be_nil
      expect(error.retry_after_known?).to be(false)
    end

    it 'maps unparseable retry_after to nil rather than 0.0' do
      error = described_class.new(status: 429, retry_after: 'banana')

      expect(error.retry_after).to be_nil
      expect(error.retry_after_known?).to be(false)
    end

    it 'reports retry_after_known? true when a numeric value was supplied' do
      expect(described_class.new(status: 429, retry_after: 0.0).retry_after_known?).to be(true)
      expect(described_class.new(status: 429, retry_after: 30).retry_after_known?).to be(true)
    end
  end

  describe 'status validation' do
    it 'accepts integer-like status values' do
      expect(described_class.new(status: 429, retry_after: 1).status).to eq(429)
      expect(described_class.new(status: '503', retry_after: 1).status).to eq(503)
    end

    it 'rejects non-integer status' do
      expect { described_class.new(status: 'fine', retry_after: 1) }.to raise_error(ArgumentError)
      expect { described_class.new(status: nil,    retry_after: 1) }.to raise_error(ArgumentError)
    end
  end

  describe 'message' do
    it 'includes status and request when provided' do
      error = described_class.new(status: 429, retry_after: 5.0, request: '/me/chats')

      expect(error.message).to include('429')
      expect(error.message).to include('/me/chats')
    end

    it 'flags retry_after=unknown when the server gave no usable header' do
      error = described_class.new(status: 429, retry_after: nil, request: '/me/chats')

      expect(error.message).to include('retry_after=unknown')
    end
  end
end
