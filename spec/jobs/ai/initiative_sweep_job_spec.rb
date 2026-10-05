require "rails_helper"

RSpec.describe Ai::InitiativeSweepJob do
  it "schedules one attempt across repeated sweeps" do
    now = Time.current
    personality = create(:personality, :active, initiative_enabled: true)
    thread = create(:conversation_thread, personality: personality)
    create(:message, conversation_thread: thread, created_at: now - 2.days)

    2.times { described_class.new.perform(now) }

    expect(personality.initiative_attempts.count).to eq(1)
    expect(OutboxEvent.where(event_key: "generate-initiative:#{personality.initiative_attempts.first.id}").count).to eq(1)
  end

  it "requeues a stale running attempt" do
    now = Time.current
    attempt = create(:initiative_attempt, status: :running, started_at: now - 2.hours)

    expect { described_class.new.perform(now) }.to have_enqueued_job(Ai::GenerateInitiativeJob).with(attempt.id)
    expect(attempt.reload).to be_pending
    expect(attempt.personality.initiative_attempts.count).to eq(1)
  end
end
