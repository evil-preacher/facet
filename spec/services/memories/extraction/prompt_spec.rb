require "rails_helper"

RSpec.describe Memories::Extraction::Prompt do
  it "uses recent user messages as context but allows only the current message as evidence" do
    personality = create(:personality, :active)
    create(:profile, user: personality.user, first_name: "Paul")
    personality.update!(name: "Lena")
    thread = create(:conversation_thread, personality: personality)
    previous_user_message = create(:message, conversation_thread: thread, content: "I do not like this film")
    user_message = create(:message, conversation_thread: thread, content: "I do not like moralizing")
    assistant_message = create(:message, :assistant, conversation_thread: thread, content: "So you like horror stories")
    run = create(:generation_run, conversation_thread: thread, personality_version: personality.current_version,
                  user_message: user_message, assistant_message: assistant_message, status: :completed)
    extraction = create(:memory_extraction, personality: personality, generation_run: run)

    payload = JSON.parse(described_class.call(extraction: extraction, active_memories: []).last.fetch(:content))

    expect(payload.fetch("current_message_id")).to eq(user_message.id)
    expect(payload.fetch("participants")).to eq(
      "user_name" => "Paul", "character_name" => "Lena"
    )
    expect(payload.fetch("allowed_message_ids")).to eq([ user_message.id ])
    expect(payload.fetch("conversation_turn")).to contain_exactly(
      { "id" => previous_user_message.id, "role" => "user", "content" => previous_user_message.content },
      { "id" => user_message.id, "role" => "user", "content" => user_message.content }
    )
    expect(payload.to_json).not_to include(assistant_message.content)
  end

  it "does not invent a user name when no profile exists" do
    personality = create(:personality, :active)
    thread = create(:conversation_thread, personality: personality)
    user_message = create(:message, conversation_thread: thread)
    run = create(:generation_run, conversation_thread: thread, personality_version: personality.current_version,
                  user_message: user_message)
    extraction = create(:memory_extraction, personality: personality, generation_run: run)

    payload = JSON.parse(described_class.call(extraction: extraction, active_memories: []).last.fetch(:content))

    expect(payload.fetch("participants")).to eq(
      "user_name" => nil, "character_name" => personality.name
    )
  end
end
