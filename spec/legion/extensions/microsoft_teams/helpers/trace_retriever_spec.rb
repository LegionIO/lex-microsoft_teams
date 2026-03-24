# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Helpers::TraceRetriever do
  let(:retriever) { Object.new.extend(described_class) }

  describe '#retrieve_context' do
    context 'when memory trace is not available' do
      before do
        allow(retriever).to receive(:memory_trace_available?).and_return(false)
      end

      it 'returns nil' do
        result = retriever.retrieve_context(message: 'hello', owner_id: 'user1')
        expect(result).to be_nil
      end
    end

    context 'when memory trace is available but store returns no traces' do
      let(:store) { double('store') }

      before do
        allow(retriever).to receive(:memory_trace_available?).and_return(true)
        allow(retriever).to receive(:shared_trace_store).and_return(store)
        allow(store).to receive(:retrieve_by_domain).and_return([])
      end

      it 'returns nil when no traces found' do
        result = retriever.retrieve_context(message: 'hello', owner_id: 'user1')
        expect(result).to be_nil
      end
    end

    context 'when memory trace is available and traces exist' do
      let(:store) { double('store') }
      let(:trace) do
        {
          trace_id:        'trace-1',
          trace_type:      :semantic,
          content_payload: 'User prefers concise responses',
          domain_tags:     %w[teams preference],
          strength:        0.8,
          last_reinforced: Time.now - 3600,
          created_at:      Time.now - 7200
        }
      end

      before do
        allow(retriever).to receive(:memory_trace_available?).and_return(true)
        allow(retriever).to receive(:shared_trace_store).and_return(store)
        allow(store).to receive(:retrieve_by_domain).and_return([trace])
      end

      it 'returns formatted context string' do
        result = retriever.retrieve_context(message: 'hello', owner_id: 'user1')
        expect(result).to be_a(String)
        expect(result).to include('## Organizational Context (from memory)')
        expect(result).to include('semantic')
        expect(result).to include('User prefers concise responses')
      end

      it 'includes chat traces when chat_id provided' do
        result = retriever.retrieve_context(message: 'hello', owner_id: 'user1', chat_id: 'chat-42')
        expect(result).to be_a(String)
      end
    end

    context 'when an error is raised' do
      before do
        allow(retriever).to receive(:memory_trace_available?).and_raise(StandardError, 'boom')
        allow(retriever).to receive(:log_trace_error)
      end

      it 'rescues and returns nil' do
        result = retriever.retrieve_context(message: 'hello', owner_id: 'user1')
        expect(result).to be_nil
      end
    end
  end

  describe '#format_trace_context (via retrieve_context)' do
    context 'when traces exceed MAX_TRACE_TOKENS budget' do
      let(:store) { double('store') }

      before do
        allow(retriever).to receive(:memory_trace_available?).and_return(true)
        allow(retriever).to receive(:shared_trace_store).and_return(store)

        # Build enough traces to exceed the 2000-token budget (each ~250 chars -> ~62 tokens)
        many_traces = (1..40).map do |i|
          {
            trace_id:        "trace-#{i}",
            trace_type:      :episodic,
            content_payload: 'x' * 200,
            domain_tags:     ['teams'],
            strength:        0.5,
            last_reinforced: Time.now,
            created_at:      Time.now
          }
        end
        allow(store).to receive(:retrieve_by_domain).and_return(many_traces)
      end

      it 'respects the token budget and truncates output' do
        result = retriever.retrieve_context(message: 'hello', owner_id: 'user1')
        # Should have some content but not all 40 traces
        expect(result).to be_a(String)
        line_count = result.split("\n").length
        expect(line_count).to be < 42 # header + at most 40 traces
      end
    end
  end

  describe '#rank_traces' do
    it 'deduplicates traces by trace_id' do
      traces = [
        { trace_id: 'a', strength: 0.9, last_reinforced: Time.now },
        { trace_id: 'a', strength: 0.9, last_reinforced: Time.now },
        { trace_id: 'b', strength: 0.5, last_reinforced: Time.now }
      ]
      result = retriever.send(:rank_traces, traces: traces, query: 'test')
      ids = result.map { |t| t[:trace_id] }
      expect(ids.uniq).to eq(ids)
      expect(result.length).to eq(2)
    end

    it 'sorts by strength descending' do
      traces = [
        { trace_id: 'low',  strength: 0.2, last_reinforced: Time.now },
        { trace_id: 'high', strength: 0.9, last_reinforced: Time.now },
        { trace_id: 'mid',  strength: 0.5, last_reinforced: Time.now }
      ]
      result = retriever.send(:rank_traces, traces: traces, query: 'test')
      expect(result.first[:trace_id]).to eq('high')
      expect(result.last[:trace_id]).to eq('low')
    end
  end

  describe '#trace_age_label' do
    it 'returns "just now" for timestamps within the last hour' do
      label = retriever.send(:trace_age_label, Time.now - 600)
      expect(label).to eq('just now')
    end

    it 'returns hours ago for timestamps within the last day' do
      label = retriever.send(:trace_age_label, Time.now - 7200)
      expect(label).to eq('2h ago')
    end

    it 'returns days ago for timestamps within the last week' do
      label = retriever.send(:trace_age_label, Time.now - 172_800)
      expect(label).to eq('2d ago')
    end

    it 'returns weeks ago for older timestamps' do
      label = retriever.send(:trace_age_label, Time.now - 1_209_600)
      expect(label).to eq('2w ago')
    end

    it 'returns "unknown age" for nil timestamp' do
      label = retriever.send(:trace_age_label, nil)
      expect(label).to eq('unknown age')
    end

    it 'returns "unknown age" on parse error' do
      label = retriever.send(:trace_age_label, 'not-a-date')
      expect(label).to eq('unknown age')
    end
  end

  describe '#memory_trace_available?' do
    it 'returns false when constant is not defined' do
      result = retriever.send(:memory_trace_available?)
      # In test env, Legion::Extensions::Agentic::Memory::Trace is not loaded
      expect(result).to be_falsy
    end
  end

  describe '#shared_trace_store' do
    it 'returns nil when memory trace constant is not defined' do
      result = retriever.send(:shared_trace_store)
      expect(result).to be_nil
    end
  end

  describe 'graceful error handling in sub-methods' do
    let(:store) { double('store') }

    before do
      allow(retriever).to receive(:shared_trace_store).and_return(store)
    end

    it 'returns empty array when retrieve_sender_traces raises' do
      allow(store).to receive(:retrieve_by_domain).and_raise(StandardError, 'db error')
      result = retriever.send(:retrieve_sender_traces, owner_id: 'user1')
      expect(result).to eq([])
    end

    it 'returns empty array when retrieve_teams_traces raises' do
      allow(store).to receive(:retrieve_by_domain).and_raise(StandardError, 'network error')
      result = retriever.send(:retrieve_teams_traces)
      expect(result).to eq([])
    end

    it 'returns empty array when retrieve_chat_traces raises' do
      allow(store).to receive(:retrieve_by_domain).and_raise(StandardError, 'timeout')
      result = retriever.send(:retrieve_chat_traces, chat_id: 'chat-1')
      expect(result).to eq([])
    end
  end
end
