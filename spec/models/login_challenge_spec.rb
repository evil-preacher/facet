require "rails_helper"

RSpec.describe LoginChallenge, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "person@example.com", confirmed_at: Time.current) }

  it { is_expected.to belong_to(:user) }

  it "accepts the issued code only once" do
    challenge, code = described_class.issue_for!(user: user, requested_ip: "127.0.0.1")

    expect(challenge.verify(code)).to be(true)
    expect(challenge.verify(code)).to be(false)
  end

  it "rejects an expired code" do
    challenge, code = described_class.issue_for!(user: user, requested_ip: "127.0.0.1")

    travel described_class::CODE_TTL + 1.second do
      expect(challenge.verify(code)).to be(false)
    end
  end

  it "invalidates the previous challenge" do
    previous, previous_code = described_class.issue_for!(user: user, requested_ip: "127.0.0.1")
    described_class.issue_for!(user: user, requested_ip: "127.0.0.1")

    expect(previous.reload.verify(previous_code)).to be(false)
  end

  it "locks after the maximum number of failed attempts" do
    challenge, code = described_class.issue_for!(user: user, requested_ip: "127.0.0.1")
    wrong_code = code == "000000" ? "999999" : "000000"
    described_class::MAX_ATTEMPTS.times { challenge.verify(wrong_code) }

    expect(challenge.verify(code)).to be(false)
  end
end
