require "rails_helper"

RSpec.describe Ai::GenerateMessageImage do
  let(:personality) do
    personality = create(:personality, name: "Leah")
    version = create(
      :personality_version,
      personality: personality,
      content: "# Identity\n\nAdult woman with dark hair.\n\n# Base character\n\nWarm and direct."
    )
    personality.update!(current_version: version, status: :active)
    personality
  end
  let(:thread) { create(:conversation_thread, personality: personality) }
  let!(:user_message) do
    create(
      :message,
      conversation_thread: thread,
      personality_version: personality.current_version,
      position: 1,
      content: "Send a photo of how you look now"
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
      content: "Here you go.",
      client_token: nil
    )
  end
  let(:message_image) do
    create(
      :message_image,
      message: assistant_message,
      source_avatar_object_key: "personalities/#{personality.id}/avatars/version-1.jpg"
    )
  end
  let(:generated_image) do
    Ai::AvatarImage.new(
      bytes: "\xFF\xD8\xFFphoto".b,
      content_type: "image/jpeg",
      request_id: "bfl-photo-1",
      model: "flux-2-klein-9b"
    )
  end
  let(:scene_description) do
    "The woman sits on a sofa in worn jeans with a laptop on her knees and coffee beside her."
  end
  let(:plan) do
    Ai::MessageImagePlan::Result.new(send_photo: true, scene_description: scene_description)
  end
  let(:planner) { class_double(Ai::MessageImagePlan, call: plan) }
  let(:generator) { instance_double(Ai::BflImageAdapter, generate: generated_image) }
  let(:storage) do
    instance_double(
      ObjectStorage::S3Store,
      download: "avatar bytes".b,
      upload: nil
    )
  end
  let(:now) { Time.zone.parse("2026-09-21 14:00:00") }

  before do
    user_message
  end

  it "uses the avatar as a reference, uploads the photo, and marks it ready" do
    result = described_class.call(
      message_image: message_image,
      planner: planner,
      generator: generator,
      storage: storage,
      now: now
    )

    expect(result.status).to eq(:completed)
    expect(storage).to have_received(:download).with(
      key: message_image.source_avatar_object_key
    )
    expect(generator).to have_received(:generate) do |arguments|
      expect(arguments[:model]).to eq("flux-2-klein-9b")
      expect(arguments[:reference_images]).to eq([ "avatar bytes".b ])
      expect(arguments[:prompt]).to include(scene_description)
      expect(arguments[:prompt]).not_to include("Warm and direct", "<character_context>")
    end
    expect(storage).to have_received(:upload).with(
      key: "messages/#{assistant_message.id}/images/#{message_image.id}.jpg",
      body: generated_image.bytes,
      content_type: "image/jpeg"
    )
    expect(message_image.reload).to have_attributes(
      status: "ready",
      content_type: "image/jpeg",
      byte_size: generated_image.bytes.bytesize,
      provider_request_id: "bfl-photo-1",
      generated_at: now,
      scene_description: scene_description,
      attempts_count: 1
    )
  end

  it "returns retryable failures to pending" do
    allow(generator).to receive(:generate).and_raise(Ai::TimeoutError)

    expect do
      described_class.call(
        message_image: message_image,
        planner: planner,
        generator: generator,
        storage: storage
      )
    end.to raise_error(Ai::RetryableMessageImageError) { |error|
      expect(error.error_code).to eq("timeout")
    }

    expect(message_image.reload).to have_attributes(
      status: "pending",
      error_code: "timeout",
      attempts_count: 1
    )
  end

  it "does not call BFL when the character declined to send a photo" do
    declined = Ai::MessageImagePlan::Result.new(send_photo: false, scene_description: "")
    allow(planner).to receive(:call).and_return(declined)

    result = described_class.call(
      message_image: message_image,
      planner: planner,
      generator: generator,
      storage: storage
    )

    expect(result.status).to eq(:declined)
    expect(message_image.reload).to be_status_declined
    expect(generator).not_to have_received(:generate)
    expect(storage).not_to have_received(:download)
  end
end
