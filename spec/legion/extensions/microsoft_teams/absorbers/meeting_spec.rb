# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Absorbers::Meeting do
  describe '.patterns' do
    it 'registers URL patterns for Teams meeting links' do
      patterns = described_class.patterns
      expect(patterns.length).to eq(2)
      expect(patterns.all? { |p| p[:type] == :url }).to be true
      expect(patterns.any? { |p| p[:value].include?('meetup-join') }).to be true
      expect(patterns.any? { |p| p[:value].include?('meet/') }).to be true
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

    let(:meetings_runner)    { double('meetings_runner') }
    let(:transcripts_runner) { double('transcripts_runner') }
    let(:ai_insights_runner) { double('ai_insights_runner') }

    before do
      allow(absorber).to receive(:meetings_runner).and_return(meetings_runner)
      allow(absorber).to receive(:transcripts_runner).and_return(transcripts_runner)
      allow(absorber).to receive(:ai_insights_runner).and_return(ai_insights_runner)
    end

    context 'when meeting cannot be resolved' do
      before do
        allow(meetings_runner).to receive(:get_meeting_by_join_url).and_return(nil)
      end

      it 'returns failure' do
        result = absorber.handle(url: 'https://teams.microsoft.com/l/meetup-join/test123')
        expect(result[:success]).to be false
        expect(result[:error]).to include('could not resolve')
      end
    end

    context 'when meeting resolves but has no id' do
      before do
        allow(meetings_runner)
          .to receive(:get_meeting_by_join_url)
          .and_return({ result: { 'value' => [{ 'subject' => 'No ID Meeting' }] } })
      end

      it 'returns failure with a clear error' do
        result = absorber.handle(url: 'https://teams.microsoft.com/l/meetup-join/test123')
        expect(result[:success]).to be false
        expect(result[:error]).to include('no id')
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
        allow(meetings_runner)
          .to receive(:get_meeting_by_join_url)
          .and_return({ result: { 'value' => [meeting_data] } })
        allow(transcripts_runner).to receive(:list_transcripts).and_return({ result: { 'value' => [] } })
        allow(ai_insights_runner).to receive(:list_meeting_ai_insights).and_return({ result: { 'value' => [] } })
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
        allow(meetings_runner)
          .to receive(:get_meeting_by_join_url)
          .and_return({ result: { 'value' => [meeting_data] } })
        allow(transcripts_runner).to receive(:list_transcripts).and_return({ result: { 'value' => [{ 'id' => 'tr-1' }] } })
        allow(transcripts_runner).to receive(:get_transcript_content).and_return({ result: 'WEBVTT transcript content here' })
        allow(ai_insights_runner).to receive(:list_meeting_ai_insights).and_return({ result: { 'value' => [] } })
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

    context 'with AI insights available' do
      let(:meeting_data) { { 'id' => 'meeting-abc', 'subject' => 'Review', 'participants' => { 'attendees' => [] } } }
      let(:insight_item) do
        {
          'id'          => 'insight-1',
          'actionItems' => [{ 'text' => 'Follow up with Alice' }, { 'text' => 'Send recap email' }]
        }
      end

      before do
        allow(meetings_runner)
          .to receive(:get_meeting_by_join_url)
          .and_return({ result: { 'value' => [meeting_data] } })
        allow(transcripts_runner).to receive(:list_transcripts).and_return({ result: { 'value' => [] } })
        allow(ai_insights_runner)
          .to receive(:list_meeting_ai_insights)
          .and_return({ result: { 'value' => [insight_item] } })
        allow(absorber).to receive(:absorb_to_knowledge)
        allow(absorber).to receive(:absorb_raw)
      end

      it 'ingests action items via absorb_to_knowledge' do
        absorber.handle(url: 'https://teams.microsoft.com/l/meetup-join/test123')
        expect(absorber).to have_received(:absorb_to_knowledge).with(
          hash_including(
            content:      "Follow up with Alice\nSend recap email",
            tags:         include('ai-insight', 'action-item'),
            content_type: 'meeting_insight'
          )
        )
      end

      it 'skips insights with no action items' do
        allow(ai_insights_runner)
          .to receive(:list_meeting_ai_insights)
          .and_return({ result: { 'value' => [{ 'id' => 'insight-2', 'actionItems' => [] }] } })
        absorber.handle(url: 'https://teams.microsoft.com/l/meetup-join/test123')
        expect(absorber).not_to have_received(:absorb_to_knowledge)
      end
    end
  end

  describe 'URL pattern matching' do
    let(:matcher) { Legion::Extensions::Absorbers::Matchers::Url }
    let(:join_pattern) { described_class.patterns.find { |p| p[:value].include?('meetup-join') }&.dig(:value) }
    let(:meet_pattern) { described_class.patterns.find { |p| p[:value].include?('meet/') }&.dig(:value) }

    it 'matches standard Teams meeting join URLs' do
      expect(join_pattern).not_to be_nil
      expect(matcher.match?(join_pattern, 'https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc123')).to be true
    end

    it 'does not match non-meeting Teams URLs' do
      expect(join_pattern).not_to be_nil
      expect(matcher.match?(join_pattern, 'https://teams.microsoft.com/l/channel/general')).to be false
    end

    it 'matches *.teams.microsoft.com/meet/* URLs' do
      expect(meet_pattern).not_to be_nil
      expect(matcher.match?(meet_pattern, 'https://tenant.teams.microsoft.com/meet/abc123')).to be true
    end
  end
end
