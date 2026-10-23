require "rails_helper"

RSpec.describe Memories::ApplyCandidates do
  let(:personality) { create(:personality, :active) }
  let(:thread) { create(:conversation_thread, personality: personality) }
  let(:message) do
    create(
      :message,
      conversation_thread: thread,
      personality_version: personality.current_version
    )
  end
  let(:generation_run) do
    create(
      :generation_run,
      conversation_thread: thread,
      personality_version: personality.current_version
    )
  end
  let(:extraction) { create(:memory_extraction, generation_run: generation_run) }

  def candidate(content:, sensitivity: "normal", action: "create", existing_memory_id: nil, kind: "fact")
    {
      "action" => action,
      "kind" => kind,
      "content" => content,
      "importance" => 70,
      "occurred_at" => nil,
      "source_message_ids" => [ message.id ],
      "existing_memory_id" => existing_memory_id,
      "sensitivity" => sensitivity
    }
  end

  it "deduplicates normalized memories and adds the new provenance" do
    existing = create(:memory, personality: personality, content: "Moving to Denver", importance: 40)

    expect do
      described_class.call(
        extraction: extraction,
        candidates: [ candidate(content: "  MOVING to Denver ") ]
      )
    end.not_to change(Memory, :count)

    expect(existing.reload.importance).to eq(70)
    expect(existing.source_messages).to contain_exactly(message)
  end

  it "does not create the same proposition under another kind" do
    existing = create(:memory, personality: personality, kind: :preference,
                      content: "The user shared a private preference", sensitivity: :sensitive)

    expect do
      described_class.call(extraction: extraction, candidates: [
        candidate(content: existing.content, kind: "fact", sensitivity: "normal")
      ])
    end.not_to change(Memory, :count)

    expect(existing.reload.source_messages).to contain_exactly(message)
    expect(existing).to be_sensitive
  end

  it "merges a close restatement with a memory from an earlier turn" do
    existing = create(:memory, personality: personality, kind: :preference,
                      content: "The user plans to visit the library on Saturday")

    expect do
      described_class.call(extraction: extraction, candidates: [
        candidate(content: "The user agreed to visit the library on Saturday",
                  kind: "preference")
      ])
    end.not_to change(Memory, :count)

    expect(existing.reload.source_messages).to contain_exactly(message)
  end

  it "does not merge statements with opposite meanings" do
    create(:memory, personality: personality, kind: :preference,
          content: "The user does not want to meet a colleague tomorrow")

    expect do
      described_class.call(extraction: extraction, candidates: [
        candidate(content: "The user wants to meet a colleague tomorrow", kind: "preference")
      ])
    end.to change(Memory, :count).by(1)
  end

  it "collapses semantic duplicates produced from one atomic statement" do
    candidates = [
      candidate(content: "The user dislikes mandatory public speaking at work",
                kind: "boundary").merge("importance" => 80),
      candidate(content: "The user dislikes required public speaking at work",
                kind: "preference").merge("importance" => 70),
      candidate(content: "The user dislikes mandatory public speaking at work",
                kind: "other").merge("importance" => 60)
    ]

    expect do
      described_class.call(extraction: extraction, candidates: candidates)
    end.to change(Memory, :count).by(1)

    expect(personality.memories.last).to have_attributes(
      kind: "boundary",
      content: "The user dislikes mandatory public speaking at work"
    )
  end

  it "keeps distinct facts from the same source message" do
    candidates = [
      candidate(content: "The user lives in Denver"),
      candidate(content: "The user likes black coffee", kind: "preference")
    ]

    expect do
      described_class.call(extraction: extraction, candidates: candidates)
    end.to change(Memory, :count).by(2)
  end

  it "does not save or reinforce low-importance scene candidates" do
    existing = create(:memory, personality: personality, content: "Alex likes coffee", importance: 60)

    result = described_class.call(extraction: extraction, candidates: [
      candidate(content: "Alex likes coffee").merge("importance" => 9),
      candidate(content: "Alex prefers the blue table in that scene", kind: "preference")
        .merge("importance" => 8)
    ])

    expect(result).to be_empty
    expect(personality.memories.count).to eq(1)
    expect(existing.reload.importance).to eq(60)
    expect(existing.source_messages).to be_empty
  end

  it "supersedes an old fact without rewriting it" do
    message.update!(content: "I actually live in Denver")
    old_memory = create(:memory, personality: personality, content: "Lives in Austin")

    result = described_class.call(
      extraction: extraction,
      candidates: [
        candidate(
          content: "Lives in Denver",
          action: "supersede",
          existing_memory_id: old_memory.id
        )
      ]
    )

    expect(old_memory.reload).to be_superseded
    expect(result.first).to have_attributes(content: "Lives in Denver", supersedes: old_memory)
  end

  it "activates sensitive memories with a classification and discards secrets" do
    results = described_class.call(
      extraction: extraction,
      candidates: [
        candidate(content: "A private personal detail", sensitivity: "sensitive"),
        candidate(content: "password: placeholder-value", sensitivity: "normal")
      ]
    )

    expect(results).to contain_exactly(have_attributes(status: "active", sensitivity: "sensitive"))
    expect(personality.memories.where("content ILIKE ?", "%password%")).not_to exist
  end

  it "keeps the old memory when superseding has no explicit correction evidence" do
    old_memory = create(:memory, personality: personality, kind: :fact, content: "Rewatched a film")

    result = described_class.call(
      extraction: extraction,
      candidates: [ candidate(content: "Too much moralizing", action: "supersede",
                                existing_memory_id: old_memory.id) ]
    )

    expect(old_memory.reload).to be_active
    expect(result.first).to have_attributes(status: "active", supersedes_id: nil)
  end

  it "does not supersede a memory of another kind" do
    old_memory = create(:memory, personality: personality, kind: :fact, content: "Rewatched a film")

    result = described_class.call(
      extraction: extraction,
      candidates: [ candidate(content: "Does not like moralizing", action: "supersede",
                                existing_memory_id: old_memory.id, kind: "preference") ]
    )

    expect(old_memory.reload).to be_active
    expect(result.first).to have_attributes(status: "active", kind: "preference", supersedes_id: nil)
  end

  it "keeps an ambiguous contradiction pending without superseding the old memory" do
    old_memory = create(:memory, personality: personality, content: "Likes coffee")

    result = described_class.call(
      extraction: extraction,
      candidates: [
        candidate(
          content: "Does not like coffee",
          action: "contradiction",
          existing_memory_id: old_memory.id
        )
      ]
    )

    expect(old_memory.reload).to be_active
    expect(result.first).to have_attributes(status: "pending", supersedes: old_memory)
  end
end
