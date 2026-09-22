require "rails_helper"

RSpec.describe Relationships::Rollback do
  it "restores an earlier summary by creating a new immutable revision" do
    state = create(:relationship_state, summary: "Current state", revision: 2)
    old_version = create(:relationship_state_version, relationship_state: state,
                         revision: 1, summary: "Earlier state")
    create(:relationship_state_version, relationship_state: state,
           revision: 2, summary: "Current state")

    restored = described_class.call(relationship_state: state, source_version: old_version)

    expect(restored).to have_attributes(
      revision: 3, summary: "Earlier state", reason: "rollback", source_version_id: old_version.id
    )
    expect(state.reload).to have_attributes(summary: "Earlier state", revision: 3)
    expect(old_version.reload.summary).to eq("Earlier state")
  end

  it "rejects a version from another personality" do
    state = create(:relationship_state)
    foreign = create(:relationship_state_version)

    expect { described_class.call(relationship_state: state, source_version: foreign) }
      .to raise_error(ArgumentError)
  end
end
