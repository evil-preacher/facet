require "rails_helper"

RSpec.describe DataExports::Build do
  it "includes uploaded image bytes in the account export" do
    user = create(:user, :confirmed)
    personality = create(:personality, :active, user: user)
    thread = create(:conversation_thread, personality: personality)
    message = create(:message, conversation_thread: thread)
    create(:message_attachment, message: message, object_key: "private/photo.jpg")
    storage = instance_double(ObjectStorage::S3Store)
    allow(storage).to receive(:download).with(key: "private/photo.jpg").and_return("photo bytes")

    exported = described_class.call(user: user, storage: storage)
    attachment = exported.fetch(:personalities).first.fetch(:threads).first.fetch(:messages).first.fetch(:attachment)

    expect(Base64.decode64(attachment.fetch(:data_base64))).to eq("photo bytes")
  end

  it "includes dynamic state provenance only for its owner" do
    user = create(:user, :confirmed)
    personality = create(:personality, :active, user: user, dynamic_state_enabled: true)
    state = personality.create_relationship_state!(trust: 55)
    state.dynamic_revisions.create!(revision: 1, event_kind: "trust", slow_state: Dynamics::Rules::BASE_SLOW.merge("trust" => 55),
                                    fast_state: Dynamics::Rules::BASE_FAST, rules_version: 1, effective_at: Time.current,
                                    source_message_ids: [])
    personality.create_emotional_state!(warmth: 20, observed_at: Time.current)
    other = create(:user, :confirmed)
    create(:personality, :active, user: other)

    exported = described_class.call(user: user)
    record = exported.fetch(:personalities).sole
    expect(record.fetch(:relationship).fetch("trust")).to eq(55)
    expect(record.fetch(:emotional_state).fetch("warmth")).to eq(20)
    expect(record.fetch(:dynamic_revisions).sole.fetch("event_kind")).to eq("trust")
  end

  it "includes initiative decisions and user quiet-hour settings" do
    user = create(:user, :confirmed)
    personality = create(:personality, :active, user: user, initiative_intensity: "normal",
                         initiative_timezone: "Almaty", initiative_quiet_start_hour: 23,
                         initiative_quiet_end_hour: 7)
    thread = create(:conversation_thread, personality: personality)
    source = create(:message, conversation_thread: thread)
    create(:initiative_attempt, personality: personality, conversation_thread: thread,
           source_message: source, status: :skipped, decision: "NO_ACTION",
           decision_reason: "quiet_hours", decided_at: Time.current)

    exported = described_class.call(user: user).fetch(:personalities).sole
    expect(exported.fetch(:details)).to include("initiative_timezone" => "Almaty",
                                                 "initiative_intensity" => "normal")
    expect(exported.fetch(:initiative_attempts).sole).to include("decision" => "NO_ACTION",
                                                                  "decision_reason" => "quiet_hours")
  end

  it "includes email consent and delivery audit in the owner's export" do
    user = create(:user, :confirmed)
    personality = create(:personality, :active, user: user, initiative_email_enabled: true)
    thread = create(:conversation_thread, personality: personality)
    source = create(:message, conversation_thread: thread)
    attempt = create(:initiative_attempt, personality: personality, conversation_thread: thread,
                     source_message: source, decision: "EMAIL")
    InitiativeEmailDelivery.create!(initiative_attempt: attempt, status: :delivered,
                                    email_message_id: "<test@facet.local>", delivered_at: Time.current)

    exported = described_class.call(user: user).fetch(:personalities).sole
    expect(exported.fetch(:details)).to include("initiative_email_enabled" => true)
    expect(exported.fetch(:initiative_attempts).sole.fetch(:email_delivery))
      .to include("status" => "delivered", "email_message_id" => "<test@facet.local>")
  end
end
