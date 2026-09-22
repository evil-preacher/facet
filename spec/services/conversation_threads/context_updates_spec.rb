require "rails_helper"

RSpec.describe ConversationThreads::ContextUpdates do
  let(:personality) { create(:personality, :active) }
  let(:thread) { create(:conversation_thread, personality: personality) }

  it "always publishes relationship work and publishes summary work at the message threshold" do
    messages = 12.times.map do |index|
      create(:message, *(index.odd? ? [ :assistant ] : []), conversation_thread: thread,
             position: index + 1, content: "Message #{index + 1}")
    end
    run = create(:generation_run, conversation_thread: thread, personality_version: personality.current_version,
                 user_message: messages[-2], assistant_message: messages[-1], status: :completed,
                 completed_at: Time.current)

    events = described_class.prepare(generation_run: run)

    expect(events.map(&:job_class)).to contain_exactly(
      "Ai::RelationshipUpdateJob", "Ai::ThreadSummaryJob"
    )
  end
end
