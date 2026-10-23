require "rails_helper"

RSpec.describe Ai::MessageImagePrompt do
  let(:personality) do
    personality = create(:personality, name: "Kara")
    version = create(
      :personality_version,
      personality: personality,
      content: <<~MARKDOWN
        # Identity

        Age: about 40 years.

        # Base character

        Adult woman with a confident posture.
      MARKDOWN
    )
    personality.update!(current_version: version, status: :active)
    personality
  end
  let(:thread) { create(:conversation_thread, personality: personality) }
  let(:message) do
    create(
      :message,
      :assistant,
      conversation_thread: thread,
      personality_version: personality.current_version,
      client_token: nil
    )
  end
  let(:message_image) do
    create(
      :message_image,
      message: message,
      scene_description: "A casual selfie in natural window light."
    )
  end

  it "renders the stored image template with the scene but omits nonvisual character context" do
    prompt = described_class.call(message_image: message_image)

    expect(prompt).to include(message_image.scene_description, "Character name: Kara")
    expect(prompt).not_to include(
      "Age: about 40 years",
      "Adult woman",
      "<character_context>"
    )
  end
end
