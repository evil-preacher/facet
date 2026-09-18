require "rails_helper"

RSpec.describe Personalities::VersionDiff do
  subject(:diff) { described_class.call(from_version: first_version, to_version: second_version) }

  let(:personality) { create(:personality) }
  let(:first_version) do
    create(
      :personality_version,
      personality: personality,
      number: 1,
      content: "# Character\nWarm\nDry humor"
    )
  end
  let(:second_version) do
    create(
      :personality_version,
      personality: personality,
      number: 2,
      content: "# Character\nWarm but candid\nDry humor\nLikes rain"
    )
  end

  it "returns a line-by-line comparison" do
    expect(diff.changes.map(&:type)).to eq(%i[unchanged changed unchanged added])
    expect(diff.changes.second).to have_attributes(old_line: "Warm", new_line: "Warm but candid")
    expect(diff.changes.last).to have_attributes(old_line: nil, new_line: "Likes rain")
  end

  it "rejects versions from different personalities" do
    other_version = create(:personality_version)

    expect do
      described_class.call(from_version: first_version, to_version: other_version)
    end.to raise_error(ArgumentError, /same personality/)
  end
end
