# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::PermissionGuard do
  let(:guard) { Object.new.extend(described_class) }

  describe '#permission_denied?' do
    it 'returns false for unknown endpoints' do
      expect(guard.permission_denied?('/me/people')).to be false
    end

    it 'returns true after a denial is recorded' do
      guard.record_denial('/me/people', 'Insufficient privileges')
      expect(guard.permission_denied?('/me/people')).to be true
    end

    it 'returns false after backoff expires' do
      guard.record_denial('/me/people', 'Insufficient privileges')
      allow(Time).to receive(:now).and_return(Time.now.utc + 61)
      expect(guard.permission_denied?('/me/people')).to be false
    end
  end

  describe '#record_denial' do
    it 'logs a warning' do
      expect(guard).to receive(:log_warn).with(%r{permission denied.*/me/people}i)
      guard.record_denial('/me/people', 'Insufficient privileges')
    end

    it 'escalates backoff on repeated denials' do
      now = Time.now.utc
      allow(Time).to receive(:now).and_return(now)

      guard.record_denial('/me/people', 'denied')
      first_retry = guard.denial_info('/me/people')[:retry_after]

      allow(Time).to receive(:now).and_return(first_retry + 1)
      guard.record_denial('/me/people', 'denied')
      second_retry = guard.denial_info('/me/people')[:retry_after]

      expect(second_retry - first_retry).to be > 60
    end

    it 'caps backoff at 8 hours' do
      now = Time.now.utc
      allow(Time).to receive(:now).and_return(now)
      10.times { guard.record_denial('/me/people', 'denied') }
      info = guard.denial_info('/me/people')
      expect(info[:retry_after]).to be <= now + 28_801
    end
  end

  describe '#reset_denials!' do
    it 'clears all recorded denials' do
      guard.record_denial('/me/people', 'denied')
      guard.reset_denials!
      expect(guard.permission_denied?('/me/people')).to be false
    end
  end

  describe '#guarded_request' do
    it 'skips the block when endpoint is denied' do
      guard.record_denial('/me/people', 'denied')
      called = false
      result = guard.guarded_request('/me/people') do
        called = true
        { result: 'ok' }
      end
      expect(called).to be false
      expect(result).to include(skipped: true)
    end

    it 'executes the block when endpoint is not denied' do
      result = guard.guarded_request('/me/people') { { result: 'ok' } }
      expect(result).to eq({ result: 'ok' })
    end

    it 'records denial on 403 response' do
      response_body = { 'error' => { 'code' => 'Authorization_RequestDenied', 'message' => 'denied' } }
      guard.guarded_request('/me/people') { { result: response_body, status: 403 } }
      expect(guard.permission_denied?('/me/people')).to be true
    end
  end
end
