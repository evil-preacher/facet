require "rails_helper"

RSpec.describe Message, type: :model do
  subject(:message) { create(:message) }

  it { is_expected.to belong_to(:conversation_thread) }
  it { is_expected.to belong_to(:personality_version) }
  it { is_expected.to define_enum_for(:role).with_values(user: "user", assistant: "assistant").backed_by_column_of_type(:string) }
  it do
    expect(message).to define_enum_for(:status)
      .with_values(streaming: "streaming", completed: "completed", failed: "failed")
      .backed_by_column_of_type(:string)
  end
  it { is_expected.to validate_length_of(:content).is_at_most(100_000) }
  it { is_expected.to validate_uniqueness_of(:client_token).allow_nil }
  it { is_expected.to validate_numericality_of(:position).only_integer.is_greater_than(0) }
  it { is_expected.to validate_uniqueness_of(:position).scoped_to(:conversation_thread_id) }

  it "requires completed messages to have content" do
    message.content = "   "

    expect(message).not_to be_valid
    expect(message.errors[:content]).to be_present
  end

  it "allows an empty streaming assistant placeholder" do
    message.assign_attributes(
      role: :assistant,
      status: :streaming,
      content: "",
      client_token: nil
    )

    expect(message).to be_valid
  end

  it "requires user messages to be completed and idempotent" do
    message.assign_attributes(status: :streaming, client_token: nil)

    expect(message).not_to be_valid
    expect(message.errors[:status]).to be_present
    expect(message.errors[:client_token]).to be_present
  end

  it "requires the personality version to match the thread" do
    message.personality_version = create(:personality_version)

    expect(message).not_to be_valid
    expect(message.errors[:personality_version]).to be_present
  end

  it "prevents deletion of a personality version used by a message" do
    persisted = create(:message)

    expect do
      persisted.personality_version.destroy!
    end.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
end
