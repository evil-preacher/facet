require "rails_helper"

RSpec.describe Personalities::AvatarGeneration::Prepare do
  let(:personality) { create(:personality) }
  let!(:version) do
    create(
      :personality_version,
      personality: personality,
      number: 1,
      content: "# Identity\n\nBlack hair"
    )
  end

  before do
    personality.update!(current_version: version, status: :active)
  end

  it "atomically marks a missing avatar pending and publishes one outbox event" do
    result = described_class.call(personality: personality, personality_version: version)

    expect(personality.reload).to have_attributes(
      avatar_status: "pending",
      avatar_source_version: version
    )
    expect(result.outbox_event).to have_attributes(
      event_key: "generate-avatar:#{personality.id}:#{version.id}",
      job_class: "Ai::GenerateAvatarJob",
      arguments: [ personality.id, version.id ]
    )

    duplicate = described_class.call(personality: personality, personality_version: version)

    expect(duplicate.outbox_event).to be_nil
    expect(OutboxEvent.where(event_key: result.outbox_event.event_key).count).to eq(1)
  end

  it "moves pending generation to the newest current version" do
    described_class.call(personality: personality, personality_version: version)
    newer_version = create(
      :personality_version,
      personality: personality,
      number: 2,
      content: "# Identity\n\nRed hair"
    )
    personality.update!(current_version: newer_version)

    result = described_class.call(personality: personality, personality_version: newer_version)

    expect(personality.reload).to have_attributes(
      avatar_status: "pending",
      avatar_source_version: newer_version
    )
    expect(result.outbox_event.arguments).to eq([ personality.id, newer_version.id ])
  end

  it "schedules a replacement when the existing avatar belongs to an older version" do
    personality.update!(
      avatar_status: :ready,
      avatar_object_key: "personalities/#{personality.id}/avatars/version-0.png",
      avatar_content_type: "image/png",
      avatar_byte_size: 128,
      avatar_generated_at: Time.current,
      avatar_source_version: version
    )
    newer_version = create(
      :personality_version,
      personality: personality,
      number: 2,
      content: "# Identity\n\nRed hair"
    )
    personality.update!(current_version: newer_version)

    result = described_class.call(personality: personality, personality_version: newer_version)

    expect(personality.reload).to have_attributes(
      avatar_status: "pending",
      avatar_object_key: "personalities/#{personality.id}/avatars/version-0.png",
      avatar_source_version: newer_version
    )
    expect(result.outbox_event.arguments).to eq([ personality.id, newer_version.id ])
  end

  it "does nothing when the requested version is no longer current" do
    newer_version = create(:personality_version, personality: personality, number: 2)
    personality.update!(current_version: newer_version)

    result = described_class.call(personality: personality, personality_version: version)

    expect(result.outbox_event).to be_nil
    expect(personality.reload).to be_avatar_missing
  end
end
