# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Absorbers::Meeting do
  describe '.patterns' do
    it 'registers URL patterns for Teams meeting links' do
      patterns = described_class.patterns
      expect(patterns.length).to eq(2)
      expect(patterns.first[:type]).to eq(:url)
      expect(patterns.first[:value]).to include('teams.microsoft.com')
    end
  end

  describe '.description' do
    it 'has a description' do
      expect(described_class.description).not_to be_nil
      expect(described_class.description).to include('meeting')
    end
  end

  describe '#handle' do
    let(:absorber) { described_class.new }

    before { absorber.job_id = 'test-meeting-001' }

    context 'when meeting cannot be resolved' do
      before do
        allow(Legion::Extensions::MicrosoftTeams::Runners::Meetings)
          .to receive(:get_meeting_by_join_url).and_return(nil)
      end

      it 'returns failure' do
        result = absorber.handle(url: 'https://teams.microsoft.com/l/meetup-join/test123')
        expect(result[:success]).to be false
        expect(result[:error]).to include('could not resolve')
      end
    end

    context 'when meeting resolves successfully' do
      let(:meeting_data) do
        {
          'id'           => 'meeting-abc',
          'subject'      => 'Sprint Planning',
          'participants' => { 'attendees' => [{ 'identity' => { 'user' => { 'displayName' => 'Alice' } } }] }
        }
      end

      before do
        allow(Legion::Extensions::MicrosoftTeams::Runners::Meetings)
          .to receive(:get_meeting_by_join_url)
          .and_return({ result: { 'value' => [meeting_data] } })
        allow(Legion::Extensions::MicrosoftTeams::Runners::Transcripts)
          .to receive(:list_transcripts).and_return({ result: { 'value' => [] } })
        allow(Legion::Extensions::MicrosoftTeams::Runners::AiInsights)
          .to receive(:list_meeting_ai_insights).and_return({ result: { 'value' => [] } })
        allow(absorber).to receive(:absorb_raw)
        allow(absorber).to receive(:absorb_to_knowledge)
      end

      it 'returns success with meeting metadata' do
        result = absorber.handle(url: 'https://teams.microsoft.com/l/meetup-join/test123')
        expect(result[:success]).to be true
        expect(result[:meeting_id]).to eq('meeting-abc')
        expect(result[:subject]).to eq('Sprint Planning')
      end

      it 'ingests participants via absorb_raw' do
        absorber.handle(url: 'https://teams.microsoft.com/l/meetup-join/test123')
        expect(absorber).to have_received(:absorb_raw).with(
          hash_including(tags: include('participants'))
        )
      end
    end

    context 'with transcripts available' do
      let(:meeting_data) { { 'id' => 'meeting-abc', 'subject' => 'Standup', 'participants' => { 'attendees' => [] } } }

      before do
        allow(Legion::Extensions::MicrosoftTeams::Runners::Meetings)
          .to receive(:get_meeting_by_join_url)
          .and_return({ result: { 'value' => [meeting_data] } })
        allow(Legion::Extensions::MicrosoftTeams::Runners::Transcripts)
          .to receive(:list_transcripts).and_return({ result: { 'value' => [{ 'id' => 'tr-1' }] } })
        allow(Legion::Extensions::MicrosoftTeams::Runners::Transcripts)
          .to receive(:get_transcript_content).and_return({ result: 'WEBVTT transcript content here' })
        allow(Legion::Extensions::MicrosoftTeams::Runners::AiInsights)
          .to receive(:list_meeting_ai_insights).and_return({ result: { 'value' => [] } })
        allow(absorber).to receive(:absorb_to_knowledge)
        allow(absorber).to receive(:absorb_raw)
      end

      it 'ingests transcript via absorb_to_knowledge' do
        absorber.handle(url: 'https://teams.microsoft.com/l/meetup-join/test123')
        expect(absorber).to have_received(:absorb_to_knowledge).with(
          hash_including(content: 'WEBVTT transcript content here', tags: include('transcript'))
        )
      end
    end
  end

  describe 'URL pattern matching' do
    let(:matcher) { Legion::Extensions::Absorbers::Matchers::Url }

    it 'matches standard Teams meeting join URLs' do
      pattern = described_class.patterns.first[:value]
      expect(matcher.match?(pattern, 'https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc123')).to be true
    end

    it 'does not match non-meeting Teams URLs' do
      pattern = described_class.patterns.first[:value]
      expect(matcher.match?(pattern, 'https://teams.microsoft.com/l/channel/general')).to be false
    end
  end
end
