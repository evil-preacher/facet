require "rails_helper"

RSpec.describe Dynamics::Interpret do
  let(:now) { Time.zone.parse("2026-10-08 12:00:00") }

  it "keeps durable context after a pause while fast feelings fade" do
    personality = create(:personality, :active, dynamic_state_enabled: true)
    relationship = personality.create_relationship_state!(trust: 65)
    emotion = personality.create_emotional_state!(warmth: 40, irritation: 40, observed_at: now)

    immediate = described_class.call(relationship_state: relationship, emotional_state: emotion, now: now)
    after_pause = described_class.call(relationship_state: relationship, emotional_state: emotion, now: now + 14.days)

    expect(immediate).to include("trust has grown", "warmth is present", "irritation is present")
    expect(after_pause).to include("trust has grown")
    expect(after_pause).not_to include("warmth is present", "irritation is present")
    expect(after_pause).not_to include("rejection", "abandonment")
  end

  it "uses recent grounded statements without turning them into character feelings or permanent facts" do
    personality = create(:personality, :active, dynamic_state_enabled: true)
    relationship = personality.create_relationship_state!
    emotion = personality.create_emotional_state!(observed_at: now)
    thread = create(:conversation_thread, personality: personality)
    source = create(:message, conversation_thread: thread, content: "I feel attracted to you.")
    relationship.dynamic_revisions.create!(revision: 1, event_kind: "attraction",
      slow_state: Dynamics::Rules::BASE_SLOW, fast_state: Dynamics::Rules::BASE_FAST,
      source_message_ids: [ source.id ], rules_version: 2, effective_at: now)

    recent = described_class.call(relationship_state: relationship, emotional_state: emotion, now: now)
    stale = described_class.call(relationship_state: relationship, emotional_state: emotion, now: now + 8.days)

    expect(recent).to include("user explicitly mentioned attraction")
    expect(recent).not_to include("character feels attraction")
    expect(stale).to eq("")
  end
end
