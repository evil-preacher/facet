require "rails_helper"

RSpec.describe ConversationThread, type: :model do
  subject(:conversation_thread) { build(:conversation_thread) }

  it { is_expected.to belong_to(:personality) }
  it { is_expected.to belong_to(:summary_through_message).class_name("Message").optional }
  it { is_expected.to have_many(:messages).dependent(:destroy) }
  it { is_expected.to have_many(:generation_runs).dependent(:destroy) }
  it { is_expected.to define_enum_for(:status).with_values(active: "active", archived: "archived").backed_by_column_of_type(:string) }
  it { is_expected.to validate_length_of(:title).is_at_most(120).allow_nil }
  it { is_expected.to validate_length_of(:summary).is_at_most(100_000).allow_nil }

  it "requires the summary boundary to belong to the thread" do
    conversation_thread.save!
    conversation_thread.summary_through_message = create(:message)

    expect(conversation_thread).not_to be_valid
    expect(conversation_thread.errors[:summary_through_message]).to be_present
  end

  it "orders active and recently used threads first" do
    personality = create(:personality, :active)
    older = create(
      :conversation_thread,
      personality: personality,
      last_message_at: 2.days.ago
    )
    newer = create(
      :conversation_thread,
      personality: personality,
      last_message_at: 1.hour.ago
    )
    archived = create(
      :conversation_thread,
      personality: personality,
      status: :archived,
      last_message_at: Time.current
    )

    expect(personality.conversation_threads.recent_first).to eq([ newer, older, archived ])
  end
end
