require "rails_helper"

RSpec.describe Personalities::Create do
  subject(:result) { described_class.call(user: user, attributes: attributes) }

  let(:user) { create(:user, :confirmed) }
  let(:attributes) do
    {
      name: "Alice",
      description: "A companion for long conversations",
      base_character: "Warm and curious, but independent-minded.",
      communication_style: "Speaks naturally without overexplaining.",
      likes: "Dark fantasy and old cities.",
      dislikes: "Corporate language.",
      relationship_context: "Has known Alex for years.",
      allowed_behaviors: "Can disagree gently.",
      forbidden_behaviors: "Does not invent shared memories."
    }
  end

  it "creates an active personality and its first version atomically" do
    expect { result }
      .to change(Personality, :count).by(1)
      .and change(PersonalityVersion, :count).by(1)

    expect(result).to be_success
    expect(result.personality).to have_attributes(
      user: user,
      name: "Alice",
      status: "active",
      conversation_model: Rails.configuration.x.ai.conversation_model,
      utility_model: Rails.configuration.x.ai.utility_model
    )
    expect(result.personality.current_version).to have_attributes(number: 1)
  end

  it "builds a stable, editable character bible" do
    content = result.personality.current_version.content

    expect(content).to include("# Identity", "Name: Alice")
    expect(content).to include("# Base character", attributes[:base_character])
    expect(content).to include("# Communication style", attributes[:communication_style])
    expect(content).to include("## Likes", attributes[:likes])
    expect(content).to include("## Dislikes", attributes[:dislikes])
    expect(content).to include("# Relationship context", attributes[:relationship_context])
    expect(content).to include("# Allowed behaviors", attributes[:allowed_behaviors])
    expect(content).to include("# Boundaries", attributes[:forbidden_behaviors])
  end

  it "queues avatar generation from the initial version" do
    expect { result }.to have_enqueued_job(Ai::GenerateAvatarJob).on_queue("avatar")

    personality = result.personality.reload
    expect(personality).to have_attributes(
      avatar_status: "pending",
      avatar_source_version: personality.current_version
    )
    expect(
      OutboxEvent.find_by(event_key: "generate-avatar:#{personality.id}:#{personality.current_version_id}")
    ).to be_dispatched
  end

  it "does not persist partial records when required input is invalid" do
    attributes[:name] = ""
    attributes[:base_character] = ""
    attributes[:communication_style] = ""

    expect { result }
      .not_to change { [ Personality.count, PersonalityVersion.count ] }

    expect(result).not_to be_success
    expect(result.errors.attribute_names).to contain_exactly(
      :name,
      :base_character,
      :communication_style
    )
  end
end
