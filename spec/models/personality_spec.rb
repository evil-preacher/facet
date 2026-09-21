require "rails_helper"

RSpec.describe Personality, type: :model do
  subject(:personality) { build(:personality) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:current_version).class_name("PersonalityVersion").optional }
  it { is_expected.to belong_to(:avatar_source_version).class_name("PersonalityVersion").optional }
  it { is_expected.to have_many(:versions).class_name("PersonalityVersion").dependent(:destroy) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_length_of(:name).is_at_most(80) }
  it { is_expected.to validate_length_of(:description).is_at_most(500) }

  it do
    expect(personality).to define_enum_for(:status)
      .with_values(draft: "draft", active: "active", archived: "archived")
      .backed_by_column_of_type(:string)
  end
  it do
    expect(personality).to define_enum_for(:avatar_status)
      .with_values(missing: "missing", pending: "pending", generating: "generating", ready: "ready", failed: "failed")
      .backed_by_column_of_type(:string)
      .with_prefix(:avatar)
  end
  it "enforces allowed statuses at the database boundary" do
    persisted = create(:personality)

    expect { persisted.update_column(:status, "unsupported") }
      .to raise_error(ActiveRecord::StatementInvalid)
  end

  it "requires a current version before becoming active" do
    personality.status = :active
    personality.current_version = nil

    expect(personality).not_to be_valid
    expect(personality.errors[:current_version]).to be_present
  end
end
