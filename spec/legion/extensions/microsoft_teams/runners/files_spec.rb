# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::MicrosoftTeams::Runners::Files do
  let(:runner) { Object.new.extend(described_class) }
  let(:graph_conn) { instance_double(Faraday::Connection) }

  before do
    allow(runner).to receive(:graph_connection).and_return(graph_conn)
  end

  describe '#list_drive_items' do
    it 'lists root drive items for the current user' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'item1', 'name' => 'Documents' }] })
      allow(graph_conn).to receive(:get)
        .with('me/drive/root/children')
        .and_return(response)

      result = runner.list_drive_items
      expect(result[:result]['value'].first['name']).to eq('Documents')
    end

    it 'uses the specified user_id' do
      response = instance_double(Faraday::Response, body: { 'value' => [] })
      allow(graph_conn).to receive(:get)
        .with('users/u1/drive/root/children')
        .and_return(response)

      result = runner.list_drive_items(user_id: 'u1')
      expect(result[:result]['value']).to eq([])
    end
  end

  describe '#get_drive_item' do
    it 'retrieves drive item metadata' do
      response = instance_double(Faraday::Response, body: { 'id' => 'item1', 'name' => 'report.docx', 'size' => 1024 })
      allow(graph_conn).to receive(:get)
        .with('users/u1/drive/items/item1')
        .and_return(response)

      result = runner.get_drive_item(item_id: 'item1', user_id: 'u1')
      expect(result[:result]['name']).to eq('report.docx')
    end

    it 'defaults to me for user_id' do
      response = instance_double(Faraday::Response, body: { 'id' => 'item2' })
      allow(graph_conn).to receive(:get)
        .with('me/drive/items/item2')
        .and_return(response)

      result = runner.get_drive_item(item_id: 'item2')
      expect(result[:result]['id']).to eq('item2')
    end
  end

  describe '#get_drive_item_content' do
    it 'downloads drive item content' do
      response = instance_double(Faraday::Response, body: 'binary-file-content')
      allow(graph_conn).to receive(:get)
        .with('users/u1/drive/items/item1/content')
        .and_return(response)

      result = runner.get_drive_item_content(item_id: 'item1', user_id: 'u1')
      expect(result[:result]).to eq('binary-file-content')
    end

    it 'defaults to me for user_id' do
      response = instance_double(Faraday::Response, body: 'content')
      allow(graph_conn).to receive(:get)
        .with('me/drive/items/item3/content')
        .and_return(response)

      result = runner.get_drive_item_content(item_id: 'item3')
      expect(result[:result]).to eq('content')
    end
  end

  describe '#list_team_drive_items' do
    it 'lists files in a team drive' do
      response = instance_double(Faraday::Response, body: { 'value' => [{ 'id' => 'titem1', 'name' => 'Shared' }] })
      allow(graph_conn).to receive(:get)
        .with('teams/t1/drive/root/children')
        .and_return(response)

      result = runner.list_team_drive_items(team_id: 't1')
      expect(result[:result]['value'].first['name']).to eq('Shared')
    end
  end
end
