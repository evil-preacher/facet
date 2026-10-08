require "rails_helper"

RSpec.describe Ai::Initiatives::Policy do
  let(:now) { Time.zone.parse("2026-10-08 12:00:00 UTC") }
  let(:personality) do
    create(:personality, :active, initiative_enabled: true, initiative_intensity: "normal",
           initiative_timezone: "UTC", initiative_quiet_start_hour: 22, initiative_quiet_end_hour: 8)
  end
  let(:thread) { create(:conversation_thread, personality: personality) }
  let!(:source) { create(:message, conversation_thread: thread, created_at: now - 2.days) }

  it "refuses a quiet-hour decision and allows daytime low intensity" do
    expect(described_class.call(personality: personality, now: now.change(hour: 23))).to eq("quiet_hours")
    expect(described_class.call(personality: personality, now: now)).to be_nil
    expect(described_class.call(personality: personality, now: now, intensity: "low")).to be_nil
  end

  it "suppresses repeated motives and unanswered initiatives" do
    sent = create(:message, :assistant, conversation_thread: thread, initiated_by: "personality",
                  read_at: now - 30.hours, created_at: now - 30.hours)
    create(:initiative_attempt, personality: personality, conversation_thread: thread, source_message: source,
           status: :completed, message: sent, motivation: "ask about work", completed_at: now - 30.hours)
    expect(described_class.call(personality: personality, now: now)).to eq("unanswered")
    create(:message, conversation_thread: thread, position: sent.position + 1, created_at: now - 12.hours)
    expect(described_class.call(personality: personality, now: now, motivation: "ask about work")).to eq("repeated_motivation")
  end

  it "enforces completed-message daily and weekly limits" do
    4.times do |index|
      sent = create(:message, :assistant, conversation_thread: thread, initiated_by: "personality",
                    created_at: now - (index + 2).days)
      create(:initiative_attempt, personality: personality, conversation_thread: thread,
             source_message: source, status: :completed, message: sent, completed_at: sent.created_at)
    end
    expect(described_class.call(personality: personality, now: now)).to eq("weekly_limit")
  end
end
