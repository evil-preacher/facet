require "rails_helper"
require_relative "../../support/ai/fake_adapter"

RSpec.describe Ai::MessageImagePlan do
  let(:personality) { create(:personality, :active, utility_model: "mistral-small-latest") }
  let(:thread) { create(:conversation_thread, personality: personality) }
  let(:user_message) do
    create(
      :message,
      conversation_thread: thread,
      personality_version: personality.current_version,
      position: 1,
      content: "Send a photo"
    )
  end
  let(:assistant_message) do
    create(
      :message,
      :assistant,
      conversation_thread: thread,
      personality_version: personality.current_version,
      position: 2,
      status: :completed,
      content: reply,
      client_token: nil
    )
  end
  let(:message_image) { create(:message_image, message: assistant_message) }
  let(:adapter) { Ai::FakeAdapter.new }
  let(:gateway) { Ai::Gateway.new(adapter: adapter) }

  before do
    create(
      :generation_run,
      conversation_thread: thread,
      personality_version: personality.current_version,
      user_message: user_message,
      assistant_message: assistant_message,
      status: :completed,
      completed_at: Time.current
    )
    create(
      :model_price,
      model: personality.utility_model,
      effective_from: 1.day.ago
    )
  end

  context "when the character sends a photo" do
    let(:reply) do
      "Here is a photo: I am sitting on a sofa with a laptop and coffee."
    end

    it "returns an authoritative visual scene" do
      adapter.enqueue_response(
        text: '{"send_photo":true,"scene_description":"She sits on a sofa with a laptop on her knees and a coffee cup beside her."}',
        request_id: "plan-1",
        model: personality.utility_model,
        usage: Ai::Usage.new(input_tokens: 30, output_tokens: 20)
      )

      plan = described_class.call(message_image: message_image, gateway: gateway)

      expect(plan).to have_attributes(
        send_photo: true,
        scene_description: "She sits on a sofa with a laptop on her knees and a coffee cup beside her."
      )
      expect(ModelCall.last).to have_attributes(
        purpose: "photo_planning",
        status: "completed",
        provider_request_id: "plan-1"
      )
    end
  end

  context "when the character refuses" do
    let(:reply) { "Photo? No. Not today." }

    it "does not authorize image generation" do
      adapter.enqueue_response(
        text: '{"send_photo":false,"scene_description":""}',
        request_id: "plan-2",
        model: personality.utility_model,
        usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
      )

      plan = described_class.call(message_image: message_image, gateway: gateway)

      expect(plan).to have_attributes(send_photo: false, scene_description: "")
    end
  end
end
