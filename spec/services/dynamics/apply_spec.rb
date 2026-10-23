require "rails_helper"

RSpec.describe Dynamics::Apply do
  let(:now) { Time.zone.parse("2026-10-08 12:00:00") }
  let(:personality) { create(:personality, :active, dynamic_state_enabled: true) }
  let(:thread) { create(:conversation_thread, personality: personality) }
  let(:user_message) { create(:message, conversation_thread: thread, position: 1, content: "I trust you", language: "ru") }
  let(:assistant_message) { create(:message, :assistant, conversation_thread: thread, position: 2) }
  let(:run) do
    create(:generation_run, conversation_thread: thread, user_message: user_message,
           assistant_message: assistant_message, status: :completed, completed_at: now)
  end

  it "applies an explicit event once and keeps its source and rules version" do
    expect { described_class.call(generation_run: run, now: now) }
      .to change(DynamicStateRevision, :count).by(1)
    state = personality.reload.relationship_state
    expect(state.trust).to eq(55)
    expect(state.closeness).to eq(0)
    expect(state.tension).to eq(0)
    revision = state.dynamic_revisions.last
    expect(revision).to have_attributes(event_kind: "trust", generation_run_id: run.id,
                                        source_message_ids: [ user_message.id ], rules_version: 2)
    expect(revision.extraction).to include("kind" => "trust", "extractor" => "explicit-v2")
    expect { described_class.call(generation_run: run, now: now) }
      .not_to change(DynamicStateRevision, :count)
  end

  it "does not mistake an imagined or hypothetical scene for a confirmed event" do
    user_message.update!(content: "*I trust you* What if I trusted you?")
    expect { described_class.call(generation_run: run, now: now) }
      .not_to change(DynamicStateRevision, :count)
    expect(DynamicStateObservation.find_by!(generation_run: run).extraction.fetch("kind")).to eq("none")
  end

  it "keeps state isolated across personalities and threads" do
    second = create(:personality, :active, user: personality.user, dynamic_state_enabled: true)
    described_class.call(generation_run: run, now: now)
    expect(second.relationship_state).to be_nil
    expect(personality.relationship_state.trust).to eq(55)
  end
end
