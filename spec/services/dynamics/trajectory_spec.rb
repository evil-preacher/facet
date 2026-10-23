require "rails_helper"

RSpec.describe "Dynamic state trajectory" do
  let(:now) { Time.zone.parse("2026-10-08 12:00:00") }
  let(:personality) { create(:personality, :active, dynamic_state_enabled: true) }
  let(:thread) { create(:conversation_thread, personality: personality) }

  def turn(content, position, at)
    user_message = create(:message, conversation_thread: thread, position: position, content: content)
    assistant_message = create(:message, :assistant, conversation_thread: thread, position: position + 1)
    run = create(:generation_run, conversation_thread: thread, user_message: user_message,
                 assistant_message: assistant_message, status: :completed, completed_at: at)
    Dynamics::Apply.call(generation_run: run, now: at)
  end

  it "decays fast emotion at different speeds without inventing a conflict" do
    turn("I trust you", 1, now)
    turn("I am angry with you", 3, now + 1.hour)
    emotion = personality.emotional_state.reload
    expect(emotion.irritation).to eq(30)
    expect(emotion.warmth).to be > 0

    Dynamics::Advance.call(personality: personality, now: now + 17.hours)
    expect(emotion.reload.irritation).to eq(8)
    expect(emotion.warmth).to be > 8
    expect(personality.relationship_state.reload.tension).to eq(8)
    count = DynamicStateRevision.count
    Dynamics::Advance.call(personality: personality, now: now + 17.hours)
    expect(DynamicStateRevision.count).to eq(count)
    expect(Dynamics::Replay.call(relationship_state: personality.relationship_state)).to be_consistent
  end

  it "resets and rolls back with immutable revisions" do
    turn("I trust you", 1, now)
    state = personality.relationship_state
    first = state.dynamic_revisions.last
    Dynamics::Reset.call(user: personality.user, personality: personality, now: now + 1.hour)
    expect(state.reload.trust).to eq(50)
    Dynamics::Rollback.call(user: personality.user, personality: personality,
                            source_revision: first, now: now + 2.hours)
    expect(state.reload.trust).to eq(55)
    expect(state.dynamic_revisions.count).to eq(3)
    expect(Dynamics::Replay.call(relationship_state: state)).to be_consistent
  end

  it "detects a current-state value that diverges from stored inputs" do
    turn("I trust you", 1, now)
    state = personality.relationship_state
    state.update_columns(trust: 90)

    expect(Dynamics::Replay.call(relationship_state: state).mismatched_revisions).to include("current")
  end

  it "keeps explicit jealousy and attraction as grounded context without assigning the user's feelings to the character" do
    turn("I feel jealous.", 1, now)
    turn("I feel attracted to you.", 3, now + 1.hour)

    state = personality.relationship_state.reload
    expect(state).to have_attributes(trust: 50, closeness: 0, tension: 0)
    expect(personality.emotional_state.reload).to have_attributes(warmth: 0, irritation: 0)
    expect(state.dynamic_revisions.pluck(:event_kind)).to eq(%w[jealousy attraction])
    expect(state.dynamic_revisions.flat_map(&:source_message_ids)).to eq(thread.messages.user.order(:position).pluck(:id))
    expect(Dynamics::Replay.call(relationship_state: state)).to be_consistent
  end

  it "replays previously recorded version-one rules after an extractor upgrade" do
    turn("I trust you", 1, now)
    revision = personality.relationship_state.dynamic_revisions.last
    revision.update!(rules_version: 1, extraction: revision.extraction.merge("extractor" => "explicit-v1"))

    expect(Dynamics::Replay.call(relationship_state: personality.relationship_state)).to be_consistent
    expect do
      Dynamics::Rules.transition(slow: {}, fast: {}, observed_at: nil,
                                 kind: "jealousy", now: now, version: 1)
    end.to raise_error(ArgumentError, "unknown event")
  end

  it "lets a later explicit boundary override earlier attraction context across threads" do
    turn("I feel attracted to you.", 1, now)
    second_thread = create(:conversation_thread, personality: personality)
    user_message = create(:message, conversation_thread: second_thread,
                          content: "I don't feel attracted to you anymore.")
    assistant_message = create(:message, :assistant, conversation_thread: second_thread,
                               position: user_message.position + 1)
    run = create(:generation_run, conversation_thread: second_thread,
                 user_message: user_message, assistant_message: assistant_message,
                 status: :completed, completed_at: now + 1.hour)
    Dynamics::Apply.call(generation_run: run, now: now + 1.hour)

    state = personality.relationship_state.reload
    context = Dynamics::Interpret.call(relationship_state: state,
                                       emotional_state: personality.emotional_state, now: now + 1.hour)
    expect(state.dynamic_revisions.pluck(:event_kind)).to eq(%w[attraction boundary])
    expect(context).not_to include("attraction")
    expect(Dynamics::Replay.call(relationship_state: state)).to be_consistent
  end
end
