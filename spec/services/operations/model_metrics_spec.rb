require "rails_helper"

RSpec.describe Operations::ModelMetrics do
  it "reports the NO_ACTION share and owner feedback without treating missing feedback as approval" do
    now = Time.current
    personality = create(:personality, :active)
    thread = create(:conversation_thread, personality: personality)
    source = create(:message, conversation_thread: thread)
    create(:initiative_attempt, personality: personality, conversation_thread: thread,
           source_message: source, decision: "NO_ACTION", status: :skipped, decided_at: now)
    sent = create(:message, :assistant, conversation_thread: thread,
                  initiated_by: "personality", initiative_feedback: "irrelevant",
                  initiative_feedback_at: now)
    create(:initiative_attempt, personality: personality, conversation_thread: thread,
           source_message: source, message: sent, decision: "IN_APP", status: :completed,
           decided_at: now, completed_at: now)

    result = described_class.call(now: now)

    expect(result).to include(initiative_no_action_share: 0.5, initiative_negative_feedback: 1)
    expect(result.fetch(:initiative_feedback)).to eq("irrelevant" => 1)
  end
end
