require "rails_helper"

RSpec.describe Ai::GenerateAvatar do
  let(:personality) { create(:personality) }
  let!(:version) do
    create(
      :personality_version,
      personality: personality,
      number: 1,
      content: "# Identity\n\nYoung woman with black hair.\n\n# Base character\n\nCalm."
    )
  end
  let(:image) do
    Ai::AvatarImage.new(
      bytes: "\x89PNG\r\n\x1A\nimage".b,
      content_type: "image/png",
      request_id: "req-image",
      model: "image-model"
    )
  end
  let(:generator) { instance_double(Ai::BflImageAdapter, generate: image) }
  let(:storage) { instance_double(ObjectStorage::S3Store, upload: nil, delete: nil) }

  before do
    personality.update!(
      current_version: version,
      status: :active,
      avatar_status: :pending,
      avatar_source_version: version
    )
  end

  it "generates, uploads, and atomically completes the avatar" do
    result = described_class.call(
      personality: personality,
      personality_version: version,
      generator: generator,
      storage: storage,
      now: Time.zone.parse("2026-09-21 12:00:00")
    )

    expected_key = "personalities/#{personality.id}/avatars/version-#{version.id}.png"
    expect(result.status).to eq(:completed)
    expect(storage).to have_received(:upload).with(
      key: expected_key,
      body: image.bytes,
      content_type: "image/png"
    )
    expect(personality.reload).to have_attributes(
      avatar_status: "ready",
      avatar_object_key: expected_key,
      avatar_content_type: "image/png",
      avatar_byte_size: image.bytes.bytesize,
      avatar_attempts_count: 1,
      avatar_generated_at: Time.zone.parse("2026-09-21 12:00:00")
    )
  end

  it "stores JPEG output with the matching extension and content type" do
    jpeg = Ai::AvatarImage.new(
      bytes: "\xFF\xD8\xFFimage".b,
      content_type: "image/jpeg",
      request_id: "req-jpeg",
      model: "image-model"
    )
    allow(generator).to receive(:generate).and_return(jpeg)

    result = described_class.call(
      personality: personality,
      personality_version: version,
      generator: generator,
      storage: storage
    )

    expected_key = "personalities/#{personality.id}/avatars/version-#{version.id}.jpg"
    expect(result.status).to eq(:completed)
    expect(storage).to have_received(:upload).with(
      key: expected_key,
      body: jpeg.bytes,
      content_type: "image/jpeg"
    )
    expect(personality.reload).to have_attributes(
      avatar_object_key: expected_key,
      avatar_content_type: "image/jpeg"
    )
  end

  it "fails without calling Mistral when selected bible sections are absent" do
    missing_context_version = create(
      :personality_version,
      personality: personality,
      number: 2,
      content: "# Communication style\n\nFriendly"
    )
    personality.update!(
      current_version: missing_context_version,
      avatar_source_version: missing_context_version
    )

    result = described_class.call(
      personality: personality,
      personality_version: missing_context_version,
      generator: generator,
      storage: storage
    )

    expect(result).to have_attributes(status: :failed, error_code: "missing_avatar_context")
    expect(generator).not_to have_received(:generate)
    expect(personality.reload).to have_attributes(
      avatar_status: "failed",
      avatar_error_code: "missing_avatar_context"
    )
  end

  it "returns retryable provider failures to pending state" do
    allow(generator).to receive(:generate).and_raise(Ai::RateLimitError)

    expect do
      described_class.call(
        personality: personality,
        personality_version: version,
        generator: generator,
        storage: storage
      )
    end.to raise_error(Ai::RetryableAvatarError) { |error|
      expect(error.error_code).to eq("rate_limit")
    }

    expect(personality.reload).to have_attributes(
      avatar_status: "pending",
      avatar_error_code: "rate_limit",
      avatar_attempts_count: 1
    )
  end

  it "does not let a stale job overwrite a newer avatar request" do
    newer_version = create(
      :personality_version,
      personality: personality,
      number: 2,
      content: "# Identity\n\nRed hair"
    )
    personality.update!(current_version: newer_version, avatar_source_version: newer_version)

    result = described_class.call(
      personality: personality,
      personality_version: version,
      generator: generator,
      storage: storage
    )

    expect(result.status).to eq(:skipped)
    expect(generator).not_to have_received(:generate)
  end
end
