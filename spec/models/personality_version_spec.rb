require "rails_helper"

RSpec.describe PersonalityVersion, type: :model do
  subject(:version) { build(:personality_version) }

  it { is_expected.to belong_to(:personality) }
  it { is_expected.to belong_to(:source_version).class_name("PersonalityVersion").optional }

  it { is_expected.to validate_presence_of(:content) }
  it { is_expected.to validate_length_of(:content).is_at_most(20_000) }
  it { is_expected.to validate_numericality_of(:number).only_integer.is_greater_than(0) }
  it { is_expected.to validate_uniqueness_of(:number).scoped_to(:personality_id) }
  it "enforces version-number uniqueness at the database boundary" do
    persisted = create(:personality_version)
    duplicate = persisted.dup

    expect { duplicate.save!(validate: false) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end
end
