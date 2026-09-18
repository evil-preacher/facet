require "rails_helper"

RSpec.describe ConversationThread, type: :model do
  subject(:conversation_thread) { build(:conversation_thread) }

  it { is_expected.to belong_to(:personality) }
  it { is_expected.to have_many(:messages).dependent(:destroy) }
  it { is_expected.to have_many(:generation_runs).dependent(:destroy) }
  it { is_expected.to define_enum_for(:status).with_values(active: "active", archived: "archived").backed_by_column_of_type(:string) }
  it { is_expected.to validate_length_of(:title).is_at_most(120).allow_nil }

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
