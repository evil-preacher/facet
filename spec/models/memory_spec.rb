require "rails_helper"

RSpec.describe Memory do
  it "normalizes content and prevents duplicate current memories" do
    personality = create(:personality, :active)
    create(:memory, personality: personality, kind: :preference, content: "  Likes COFFEE ")

    duplicate = build(:memory, personality: personality, kind: :preference, content: "likes coffee")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:normalized_content]).to be_present
  end

  it "allows a superseded memory to retain the same normalized content" do
    personality = create(:personality, :active)
    old_memory = create(:memory, personality: personality, content: "Lives in Austin")
    old_memory.update!(status: :superseded)

    expect do
      create(:memory, personality: personality, content: "Lives in Austin", supersedes: old_memory)
    end.to change(described_class, :count).by(1)
  end

  it "excludes deleted memories from retrieval immediately" do
    memory = create(:memory)

    Memories::Delete.call(memory: memory, user: memory.personality.user)

    expect(memory.reload).to be_deleted
    expect(described_class.available_for_retrieval).not_to include(memory)
  end
end
