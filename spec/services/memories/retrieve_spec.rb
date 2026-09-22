require "rails_helper"

RSpec.describe Memories::Retrieve do
  let(:personality) { create(:personality, :active) }

  it "ranks relevant active memories while isolating ownership and status" do
    relevant = create(:memory, personality: personality, content: "The user always chooses a window seat", importance: 55)
    important = create(:memory, personality: personality, content: "The user likes quiet mornings", importance: 100)
    deleted = create(:memory, personality: personality, content: "Window seat was deleted", status: :deleted, deleted_at: Time.current)
    pending = create(:memory, personality: personality, content: "Window seat pending", status: :pending)
    foreign = create(:memory, content: "The user always chooses a window seat", importance: 100)

    result = described_class.call(personality: personality, query: "Which window seat should I book?")

    expect(result.memories.first).to eq(relevant)
    expect(result.memories).to include(important)
    expect(result.memories).not_to include(deleted, pending, foreign)
    expect(result.diagnostics.first).to include("memory_id" => relevant.id, "rank" => 1)
    expect(result.diagnostics.first.fetch("reasons")).to include("importance" => 55, "text_relevance" => be > 0)
  end

  it "enforces both result count and token budget" do
    memories = create_list(:memory, 3, personality: personality)
    counter = instance_double(Ai::TokenCounter)
    allow(counter).to receive(:count).and_return(6)

    result = described_class.call(
      personality: personality, query: "", limit: 3, token_budget: 12, token_counter: counter
    )

    expect(result.memories).to contain_exactly(*memories.first(2))
    expect(result.diagnostics.sum { |item| item.fetch("token_count") }).to eq(12)
  end
end
