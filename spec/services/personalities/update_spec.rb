require "rails_helper"

RSpec.describe Personalities::Update do
  subject(:result) do
    described_class.call(
      personality: personality,
      author: personality.user,
      attributes: {
        name: "New Alice",
        description: "New description",
        character_bible: new_content,
        change_note: "Character clarified"
      }
    )
  end

  let(:personality) { create(:personality, name: "Alice") }
  let!(:first_version) do
    create(:personality_version, personality: personality, number: 1, content: "# Original")
  end
  let(:new_content) { "# Updated\n\nA fuller character bible." }

  before do
    personality.update!(current_version: first_version)
  end

  it "updates metadata and creates a new immutable version for changed content" do
    expect { result }.to change(personality.versions, :count).by(1)

    expect(result).to be_success
    expect(personality.reload).to have_attributes(name: "New Alice", description: "New description")
    expect(personality.current_version).to have_attributes(
      number: 2,
      content: new_content,
      author: personality.user,
      change_note: "Character clarified"
    )
    expect(first_version.reload.content).to eq("# Original")
  end

  it "creates an audit version when the content did not change" do
    new_content.replace(first_version.content)

    expect { result }.to change(personality.versions, :count).by(1)

    expect(result).to be_success
    expect(personality.reload.name).to eq("New Alice")
    expect(personality.current_version).to have_attributes(number: 2, content: first_version.content)
  end

  it "queues generation when the edited personality has no avatar" do
    expect { result }.to have_enqueued_job(Ai::GenerateAvatarJob).on_queue("avatar")

    expect(personality.reload).to have_attributes(
      avatar_status: "pending",
      avatar_source_version: personality.current_version
    )
  end

  it "regenerates an existing avatar from the edited version" do
    personality.update!(
      avatar_status: :ready,
      avatar_object_key: "personalities/#{personality.id}/avatars/original.png",
      avatar_content_type: "image/png",
      avatar_byte_size: 128,
      avatar_generated_at: Time.current,
      avatar_source_version: first_version
    )
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { result }.to have_enqueued_job(Ai::GenerateAvatarJob).on_queue("avatar")

    expect(personality.reload).to have_attributes(
      avatar_status: "pending",
      avatar_object_key: "personalities/#{personality.id}/avatars/original.png",
      avatar_source_version: personality.current_version
    )
  end

  it "does not persist any changes when input is invalid" do
    new_content.replace("")

    expect { result }.not_to change(personality.versions, :count)

    expect(result).not_to be_success
    expect(personality.reload.name).to eq("Alice")
    expect(personality.current_version).to eq(first_version)
  end
end
