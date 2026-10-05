require "rails_helper"

RSpec.describe Ai::Initiatives::Eligibility do
  let(:now) { Time.current }
  let(:personality) { create(:personality, :active, initiative_enabled: true) }
  let(:thread) { create(:conversation_thread, personality: personality) }
  let!(:source) { create(:message, conversation_thread: thread, created_at: now - 2.days) }

  def eligible?
    described_class.call(personality: personality, now: now).eligible
  end

  it "selects the latest active conversation after the idle period" do
    expect(eligible?).to be(true)
    expect(described_class.call(personality: personality, now: now).thread).to eq(thread)
  end

  it "does not initiate when disabled, archived, or too soon after a user message" do
    personality.update!(initiative_enabled: false)
    expect(eligible?).to be(false)
    personality.update!(initiative_enabled: true, status: :archived)
    expect(eligible?).to be(false)
    personality.update!(status: :active)
    source.update!(created_at: now - 1.hour)
    expect(eligible?).to be(false)
  end

  it "does not initiate into an archived conversation" do
    thread.update!(status: :archived)
    expect(eligible?).to be(false)
  end

  it "waits after a recent ordinary assistant reply" do
    create(:message, :assistant, conversation_thread: thread, created_at: now - 1.hour)
    expect(eligible?).to be(false)
  end

  it "respects cooldown and an unread initiative" do
    create(:initiative_attempt, personality: personality, conversation_thread: thread,
           source_message: source, created_at: now - 1.hour, status: :skipped)
    expect(eligible?).to be(false)
    personality.initiative_attempts.delete_all
    create(:message, :assistant, conversation_thread: thread, initiated_by: "personality", read_at: nil)
    expect(eligible?).to be(false)
  end

  it "stops before a model call when the budget is exhausted" do
    personality.user.update!(monthly_ai_limit_microusd: 0)
    expect(eligible?).to be(false)
  end

  it "waits while an ordinary reply is still generating" do
    run = create(:generation_run, conversation_thread: thread, user_message: source,
                personality_version: source.personality_version, status: :pending)
    expect(eligible?).to be(false)
    run.update!(status: :completed, completed_at: now)
    expect(eligible?).to be(true)
  end
end
