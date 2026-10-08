require "rails_helper"

RSpec.describe "Dynamic state deletion" do
  it "removes observations, emotional state and revisions with the personality" do
    personality = create(:personality, :active, dynamic_state_enabled: true)
    thread = create(:conversation_thread, personality: personality)
    user_message = create(:message, conversation_thread: thread, position: 1, content: "I trust you")
    assistant_message = create(:message, :assistant, conversation_thread: thread, position: 2)
    run = create(:generation_run, conversation_thread: thread, user_message: user_message,
                 assistant_message: assistant_message, status: :completed, completed_at: Time.current)
    Dynamics::Apply.call(generation_run: run)

    expect do
      Personalities::Destroy.call(user: personality.user, personality: personality)
    end.to change(DynamicStateRevision, :count).by(-1)
      .and change(DynamicStateObservation, :count).by(-1)
      .and change(EmotionalState, :count).by(-1)
    expect(Personality.exists?(personality.id)).to be(false)
  end
end
