require "rails_helper"

RSpec.describe ConversationThreads::Create do
  subject(:result) do
    described_class.call(
      personality: personality,
      user: user,
      attributes: {
        content: initial_message,
        client_token: "11111111-1111-4111-8111-111111111111",
        user_id: create(:user).id
      }
    )
  end

  let(:user) { create(:user, :confirmed) }
  let!(:personality) do
    Personalities::Create.call(
      user: user,
      attributes: {
        name: "Alice",
        base_character: "Curious.",
        communication_style: "Speaks naturally."
      }
    ).personality
  end
  let(:initial_message) { "  Shall we discuss old cities and rain?  " }

  before { allow(Rails.configuration.x.ai).to receive(:provider).and_return("mistral") }

  it "atomically creates a thread, message, assistant placeholder, and generation" do
    expect do
      expect do
        expect { result }.to have_enqueued_job(Ai::GenerateReplyJob).once
      end.to change(ConversationThread, :count).by(1)
        .and change(GenerationRun, :count).by(1)
        .and change(OutboxEvent, :count).by(1)
    end.to change(Message, :count).by(2)

    expect(result).to be_success
    expect(result.conversation_thread).to have_attributes(
      personality: personality,
      title: "Shall we discuss old cities and rain?",
      status: "active"
    )
    expect(result.message).to have_attributes(
      conversation_thread: result.conversation_thread,
      personality_version: personality.current_version,
      role: "user",
      status: "completed",
      language: "en",
      position: 1,
      content: "Shall we discuss old cities and rain?"
    )
    expect(result.conversation_thread.last_message_at).to eq(result.message.created_at)
    expect(result.assistant_message).to have_attributes(role: "assistant", status: "streaming", content: "")
    expect(result.generation_run.user_message).to eq(result.message)
  end

  it "pins the active platform prompt and provider on the generation" do
    platform_prompt = create(:ai_platform_prompt, provider: "mistral")

    expect(result).to be_success
    expect(result.generation_run).to have_attributes(
      ai_provider: "mistral",
      ai_platform_prompt: platform_prompt
    )
  end

  it "fails before creating records when a required platform prompt is missing" do
    allow(Rails.configuration.x.ai).to receive(:platform_prompt_required).and_return(true)

    expect do
      expect { result }.to raise_error(Ai::ValidationError, /No active conversation platform prompt/)
    end.not_to change(ConversationThread, :count)
  end

  it "derives a compact title from the first message" do
    initial_message.replace("A   very long\nmessage " + ("about memories " * 12))

    expect(result).to be_success
    expect(result.conversation_thread.title.length).to be <= 80
    expect(result.conversation_thread.title).not_to include("\n")
    expect(result.conversation_thread.title).not_to include("  ")
  end

  it "is idempotent when the create request is repeated" do
    first_result = result

    expect do
      @repeated_result = described_class.call(
        personality: personality,
        user: user,
        attributes: {
          content: "Duplicate",
          client_token: "11111111-1111-4111-8111-111111111111"
        }
      )
    end.to change(ConversationThread, :count).by(0)
      .and change(GenerationRun, :count).by(0)

    expect(first_result).to be_created
    expect(@repeated_result).to be_success
    expect(@repeated_result).not_to be_created
    expect(@repeated_result.conversation_thread).to eq(first_result.conversation_thread)
    expect(@repeated_result.message).to eq(first_result.message)
  end

  it "does not accept ownership from form attributes" do
    expect(result).to be_success
    expect(result.conversation_thread.personality.user).to eq(user)
  end

  it "rejects an empty first message without partial records" do
    initial_message.replace("   ")

    expect do
      expect { result }.not_to change(ConversationThread, :count)
    end.not_to change(Message, :count)

    expect(result).not_to be_success
    expect(result.errors[:content]).to be_present
  end

  it "does not create threads for an archived personality" do
    personality.update!(status: :archived)

    expect { result }.not_to change(ConversationThread, :count)
    expect(result).not_to be_success
  end
end
