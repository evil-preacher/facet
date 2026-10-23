require "rails_helper"

RSpec.describe Profile, type: :model do
  subject(:profile) { described_class.new }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:first_name) }
  it { is_expected.to validate_presence_of(:last_name) }
  it { is_expected.to validate_presence_of(:gender) }

  it "allows an omitted birth date" do
    profile = described_class.new(
      user: User.new(email: "person@example.com"),
      first_name: "John",
      last_name: "Johnson",
      gender: :male
    )

    expect(profile).to be_valid
  end

  it "rejects a future birth date" do
    profile = described_class.new(birth_date: 1.day.from_now.to_date)
    profile.validate

    expect(profile.errors[:birth_date]).to include("cannot be in the future")
  end
end
