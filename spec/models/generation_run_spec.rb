require "rails_helper"

RSpec.describe GenerationRun, type: :model do
  subject(:generation_run) { create(:generation_run) }

  it { is_expected.to belong_to(:conversation_thread) }
  it { is_expected.to belong_to(:personality_version) }
  it { is_expected.to belong_to(:user_message).class_name("Message") }
  it { is_expected.to belong_to(:assistant_message).class_name("Message").optional }
  it { is_expected.to belong_to(:ai_platform_prompt).optional }
  it do
    expect(generation_run).to define_enum_for(:status)
      .with_values(
        pending: "pending",
        running: "running",
        completed: "completed",
        failed: "failed",
        stopped: "stopped"
      )
      .backed_by_column_of_type(:string)
  end
  it { is_expected.to validate_presence_of(:idempotency_key) }
  it { is_expected.to validate_uniqueness_of(:idempotency_key) }
  it { is_expected.to validate_numericality_of(:attempts_count).only_integer.is_greater_than_or_equal_to(0) }

  it "requires the user message to belong to the run thread and have the user role" do
    generation_run.user_message = create(
      :message,
      role: :assistant,
      client_token: nil,
      conversation_thread: generation_run.conversation_thread
    )

    expect(generation_run).not_to be_valid
    expect(generation_run.errors[:user_message]).to be_present
  end

  it "requires the assistant message to belong to the run thread and have the assistant role" do
    generation_run.assistant_message = create(
      :message,
      conversation_thread: create(:conversation_thread)
    )

    expect(generation_run).not_to be_valid
    expect(generation_run.errors[:assistant_message]).to be_present
  end

  it "requires the personality version to belong to the thread personality" do
    generation_run.personality_version = create(:personality_version)

    expect(generation_run).not_to be_valid
    expect(generation_run.errors[:personality_version]).to be_present
  end
  it "requires the platform prompt to match the run provider" do
    generation_run.ai_platform_prompt = create(:ai_platform_prompt, provider: "openai")

    expect(generation_run).not_to be_valid
    expect(generation_run.errors[:ai_platform_prompt]).to be_present
  end
end
