# frozen_string_literal: true

RSpec.describe Legion::Extensions::MicrosoftTeams do
  it 'has a version number' do
    expect(Legion::Extensions::MicrosoftTeams::VERSION).not_to be_nil
  end

  it 'defines the module' do
    expect(described_class).to be_a(Module)
  end
end
