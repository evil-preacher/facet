require "rails_helper"

RSpec.describe User, type: :model do
  it { is_expected.to have_one(:profile).dependent(:destroy) }
  it { is_expected.to have_many(:login_challenges).dependent(:destroy) }
  it { is_expected.to have_many(:personalities).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:email) }

  it "normalizes email before validation" do
    user = described_class.create!(email: "  Person@Example.COM ")

    expect(user.email).to eq("person@example.com")
  end

  it "rejects duplicate normalized emails" do
    described_class.create!(email: "person@example.com")
    duplicate = described_class.new(email: "PERSON@example.com")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to be_present
  end
end
