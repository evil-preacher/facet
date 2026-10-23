require "rails_helper"

RSpec.describe Personalities::Rollback do
  subject(:result) do
    described_class.call(
      personality: personality,
      source_version: first_version,
      author: personality.user,
      change_note: "Restored the original character"
    )
  end

  let(:personality) { create(:personality) }
  let!(:first_version) do
    create(:personality_version, personality: personality, number: 1, content: "# Original")
  end
  let!(:second_version) do
    create(:personality_version, personality: personality, number: 2, content: "# Revised")
  end

  before do
    personality.update!(current_version: second_version, status: :active)
  end

  it "creates a new version from the selected source without changing history" do
    expect { result }.to change(personality.versions, :count).by(1)

    expect(result).to be_success
    expect(result.version).to have_attributes(
      number: 3,
      content: "# Original",
      source_version: first_version,
      author: personality.user,
      change_note: "Restored the original character"
    )
    expect(personality.reload.current_version).to eq(result.version)
    expect(first_version.reload.content).to eq("# Original")
    expect(second_version.reload.content).to eq("# Revised")
  end

  it "rejects a source version owned by another personality" do
    foreign_version = create(:personality_version)

    foreign_result = described_class.call(
      personality: personality,
      source_version: foreign_version,
      author: personality.user
    )

    expect(foreign_result).not_to be_success
    expect(foreign_result.errors[:source_version]).to be_present
  end
end
