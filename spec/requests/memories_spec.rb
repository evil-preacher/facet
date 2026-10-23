require "rails_helper"

RSpec.describe "Memories", type: :request do
  let(:user) { create(:user, :confirmed) }
  let!(:profile) { create(:profile, user: user) }
  let(:personality) { create(:personality, :active, user: user) }

  def sign_in(user_to_sign_in = user)
    challenge, code = LoginChallenge.issue_for!(user: user_to_sign_in, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  it "requires authentication" do
    get personality_memories_path(personality)

    expect(response).to redirect_to(root_path)
  end

  it "lists current memories with filters and does not list deleted history" do
    preference = create(:memory, personality: personality, kind: :preference, content: "Likes tea")
    create(:memory, personality: personality, kind: :preference, content: "Likes coffee")
    create(:memory, personality: personality, kind: :fact, content: "Lives in Denver")
    create(
      :memory,
      personality: personality,
      kind: :fact,
      content: "Old fact",
      status: :deleted,
      deleted_at: Time.current
    )
    sign_in

    get personality_memories_path(personality, kind: "preference")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(preference.content, "Preference", "Automatic memory")
    document = Nokogiri::HTML(response.body)
    filter_labels = document.css("nav a").map { |link| link.text.squish }
    expect(document.text).to include("Total memories: 3")
    expect(filter_labels).to include("All 3", "Fact 1", "Preference 2", "Other 0")
    expect(response.body).not_to include("Old fact")
  end

  it "does not expose another user's memories" do
    other_user = create(:user, :confirmed)
    other_personality = create(:personality, :active, user: other_user)
    create(:memory, personality: other_personality, content: "Another person's fact")
    sign_in

    get personality_memories_path(other_personality)

    expect(response).to have_http_status(:not_found)
  end

  it "corrects a memory by creating a replacement and retaining history" do
    memory = create(:memory, personality: personality, content: "Lives in Austin")
    sign_in

    expect do
      patch personality_memory_path(personality, memory), params: {
        memory: {
          content: "Lives in Denver",
          kind: "fact",
          importance: 90
        }
      }
    end.to change(personality.memories, :count).by(1)

    expect(response).to redirect_to(personality_memories_path(personality))
    expect(memory.reload).to be_superseded
    expect(personality.memories.active.last).to have_attributes(
      content: "Lives in Denver",
      importance: 90,
      origin: "user",
      supersedes: memory
    )
  end

  it "can change only importance without violating current-memory uniqueness" do
    memory = create(:memory, personality: personality, content: "Likes tea", importance: 40)
    sign_in

    patch personality_memory_path(personality, memory), params: {
      memory: { content: memory.content, kind: memory.kind, importance: 75 }
    }

    expect(response).to redirect_to(personality_memories_path(personality))
    expect(memory.reload).to be_superseded
    expect(personality.memories.active.last).to have_attributes(content: "Likes tea", importance: 75)
  end

  it "deletes a memory from the current set immediately" do
    memory = create(:memory, personality: personality)
    sign_in

    delete personality_memory_path(personality, memory)

    expect(response).to redirect_to(personality_memories_path(personality))
    expect(memory.reload).to be_deleted
    expect(personality.memories.current).not_to include(memory)
  end

  it "clears every memory and its sources for one personality" do
    previous = create(:memory, personality: personality, content: "Old fact", status: :superseded)
    current = create(:memory, personality: personality, content: "New fact", supersedes: previous)
    create(:memory, personality: personality, status: :pending)
    create(:memory, personality: personality, status: :deleted, deleted_at: Time.current)
    source = create(:memory_source, memory: current)
    other_personality = create(:personality, :active, user: user)
    other_memory = create(:memory, personality: other_personality)
    sign_in

    get personality_memories_path(personality)
    expect(response.body).to include("Clear all memories")

    delete clear_personality_memories_path(personality)

    expect(response).to redirect_to(personality_memories_path(personality))
    expect(personality.memories).to be_empty
    expect(MemorySource.exists?(source.id)).to be(false)
    expect(Message.exists?(source.message_id)).to be(true)
    expect(Memory.exists?(other_memory.id)).to be(true)

    get personality_memories_path(personality)
    expect(response.body).not_to include("Clear all memories")
  end

  it "does not clear another user's memory" do
    other_user = create(:user, :confirmed)
    other_personality = create(:personality, :active, user: other_user)
    memory = create(:memory, personality: other_personality)
    sign_in

    delete clear_personality_memories_path(other_personality)

    expect(response).to have_http_status(:not_found)
    expect(memory.reload).to be_persisted
  end

  it "approves a sensitive pending replacement before superseding the old fact" do
    old_memory = create(:memory, personality: personality, content: "No travel restrictions")
    pending = create(
      :memory,
      personality: personality,
      content: "There is a travel restriction",
      status: :pending,
      sensitivity: :sensitive,
      supersedes: old_memory
    )
    sign_in

    patch approve_personality_memory_path(personality, pending)

    expect(pending.reload).to be_active
    expect(old_memory.reload).to be_superseded
  end

  it "resolves the original conflict when the user edits a pending replacement" do
    old_memory = create(:memory, personality: personality, content: "Likes coffee")
    pending = create(
      :memory,
      personality: personality,
      content: "Does not like coffee",
      status: :pending,
      supersedes: old_memory
    )
    sign_in

    patch personality_memory_path(personality, pending), params: {
      memory: {
        content: "Prefers tea but sometimes drinks coffee",
        kind: "preference",
        importance: 75
      }
    }

    replacement = personality.memories.active.last
    expect(old_memory.reload).to be_superseded
    expect(pending.reload).to be_superseded
    expect(replacement).to have_attributes(
      content: "Prefers tea but sometimes drinks coffee",
      supersedes: old_memory
    )
  end

  it "turns automatic extraction off without deleting existing memories" do
    memory = create(:memory, personality: personality)
    sign_in

    patch settings_personality_memories_path(personality), params: {
      personality: { automatic_memory_enabled: "0" }
    }

    expect(response).to redirect_to(personality_memories_path(personality))
    expect(personality.reload).not_to be_automatic_memory_enabled
    expect(memory.reload).to be_persisted
  end
end
