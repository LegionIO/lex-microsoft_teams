# frozen_string_literal: true

RSpec.describe 'MicrosoftTeams runner definition DSL wiring' do
  let(:runner_files) do
    Dir[File.expand_path('../../../../../lib/legion/extensions/microsoft_teams/runners/*.rb', __dir__)]
  end

  it 'extends Definitions before calling definition in runner modules' do
    offenders = runner_files.filter_map do |path|
      source = File.read(path)
      next unless source.include?('definition :')

      extend_index = source.index('extend Legion::Extensions::Definitions')
      definition_index = source.index('definition :')
      next if extend_index && extend_index < definition_index

      File.basename(path)
    end

    expect(offenders).to eq([])
  end

  it 'exposes inputs properties matching method kwargs for MCP-exposed list methods' do
    expected = {
      Legion::Extensions::MicrosoftTeams::Runners::Messages        => {
        list_chat_messages:   %i[chat_id top max_pages orderby filter],
        list_message_replies: %i[chat_id message_id top max_pages]
      },
      Legion::Extensions::MicrosoftTeams::Runners::Chats           => {
        list_chats: %i[top max_pages expand filter orderby]
      },
      Legion::Extensions::MicrosoftTeams::Runners::ChannelMessages => {
        list_channel_messages:        %i[team_id channel_id top max_pages expand],
        list_channel_message_replies: %i[team_id channel_id message_id top max_pages]
      },
      Legion::Extensions::MicrosoftTeams::Runners::Transcripts     => {
        list_transcripts:       %i[meeting_id top max_pages],
        get_transcript_content: %i[meeting_id transcript_id format]
      },
      Legion::Extensions::MicrosoftTeams::Runners::Teams           => {
        list_joined_teams: %i[filter select],
        list_team_members: %i[team_id top max_pages filter]
      }
    }

    expected.each do |mod, methods|
      methods.each do |method_name, expected_props|
        defn = mod.definitions[method_name]
        expect(defn).not_to be_nil, "#{mod}##{method_name}: no definition found"
        props = defn[:inputs][:properties].keys.map(&:to_sym)
        expected_props.each do |prop|
          expect(props).to include(prop),
                           "#{mod}##{method_name}: missing input property :#{prop} (has #{props})"
        end
      end
    end
  end
end
