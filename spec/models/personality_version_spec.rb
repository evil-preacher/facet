require "rails_helper"

RSpec.describe PersonalityVersion, type: :model do
  subject(:version) { build(:personality_version) }

  it { is_expected.to belong_to(:personality) }
  it { is_expected.to belong_to(:author).class_name("User") }
  it { is_expected.to belong_to(:source_version).class_name("PersonalityVersion").optional }

  it { is_expected.to validate_presence_of(:content) }
  it { is_expected.to validate_length_of(:content).is_at_most(50_000) }
  it { is_expected.to validate_length_of(:change_note).is_at_most(500).allow_nil }
  it { is_expected.to validate_numericality_of(:number).only_integer.is_greater_than(0) }
  it { is_expected.to validate_uniqueness_of(:number).scoped_to(:personality_id) }

  it "requires the author to own the personality" do
    version.author = create(:user)

    expect(version).not_to be_valid
    expect(version.errors[:author]).to be_present
  end

  it "requires the source version to belong to the same personality" do
    version.source_version = create(:personality_version)

    expect(version).not_to be_valid
    expect(version.errors[:source_version]).to be_present
  end

  it "keeps persisted audit data immutable" do
    persisted = create(:personality_version)

    expect do
      persisted.update!(content: "# Rewritten history")
    end.to raise_error(ActiveRecord::ReadonlyAttributeError)

    expect(persisted.reload.content).not_to eq("# Rewritten history")
  end

  it "enforces version-number uniqueness at the database boundary" do
    persisted = create(:personality_version)
    duplicate = persisted.dup

    expect { duplicate.save!(validate: false) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "enforces change-note length at the database boundary" do
    persisted = create(:personality_version)

    expect do
      PersonalityVersion.insert_all!(
        [ {
          personality_id: persisted.personality_id,
          author_id: persisted.author_id,
          number: persisted.number + 1,
          content: "# Invalid note",
          change_note: "x" * 501,
          created_at: Time.current,
          updated_at: Time.current
        } ]
      )
    end.to raise_error(ActiveRecord::StatementInvalid)
  end
end
