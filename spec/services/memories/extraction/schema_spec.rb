require "rails_helper"

RSpec.describe Memories::Extraction::Schema do
  it "uses the compact JSON Schema subset accepted by Mistral" do
    serialized = described_class::RESPONSE_SCHEMA.to_json

    expect(serialized).not_to match(/minLength|maxLength|minItems|maxItems|uniqueItems|minimum|maximum|format/)
  end

  let(:candidate) do
    {
      action: "create",
      kind: "fact",
      content: "The user is moving to Denver",
      evidence_quote: "I am moving to Denver",
      importance: 85,
      occurred_at: "2026-09-25T09:00:00+05:00",
      source_message_ids: [ 12 ],
      existing_memory_id: nil,
      sensitivity: "normal"
    }
  end

  it "parses a strict candidate and converts its timestamp" do
    parsed = described_class.parse(
      text: { candidates: [ candidate ] }.to_json,
      allowed_message_ids: [ 12 ],
      allowed_memory_ids: [],
      source_message_texts: { 12 => "I am moving to Denver on Friday" }
    )

    expect(parsed.first.fetch("occurred_at")).to eq(Time.iso8601(candidate.fetch(:occurred_at)))
  end

  it "rejects hallucinated source ids and additional properties" do
    candidate[:source_message_ids] = [ 999 ]
    candidate[:reasoning] = "private chain of thought"

    expect do
      described_class.parse(
        text: { candidates: [ candidate ] }.to_json,
        allowed_message_ids: [ 12 ],
        allowed_memory_ids: [],
        source_message_texts: { 12 => "I am moving to Denver on Friday" }
      )
    end.to raise_error(described_class::InvalidOutput)
  end

  it "requires supersede operations to reference a supplied active memory" do
    candidate[:action] = "supersede"
    candidate[:existing_memory_id] = 44

    expect do
      described_class.parse(
        text: { candidates: [ candidate ] }.to_json,
        allowed_message_ids: [ 12 ],
        allowed_memory_ids: [ 43 ],
        source_message_texts: { 12 => "I am moving to Denver on Friday" }
      )
    end.to raise_error(described_class::InvalidOutput)
  end

  it "accepts up to three recent user messages as provenance" do
    candidate[:source_message_ids] = [ 10, 11, 12 ]

    parsed = described_class.parse(
      text: { candidates: [ candidate ] }.to_json,
      allowed_message_ids: [ 10, 11, 12 ],
      allowed_memory_ids: [],
      source_message_texts: { 12 => "I am moving to Denver on Friday" }
    )

    expect(parsed.first.fetch("source_message_ids")).to eq([ 10, 11, 12 ])
  end

  it "accepts an ambiguous contradiction only against a supplied memory" do
    candidate[:action] = "contradiction"
    candidate[:existing_memory_id] = 44

    parsed = described_class.parse(
      text: { candidates: [ candidate ] }.to_json,
      allowed_message_ids: [ 12 ],
      allowed_memory_ids: [ 44 ],
      source_message_texts: { 12 => "I am moving to Denver on Friday" }
    )

    expect(parsed.first.fetch("action")).to eq("contradiction")
  end

  it "rejects a character question presented as a user preference" do
    candidate[:kind] = "preference"
    candidate[:content] = "Alex prefers hiking"
    candidate[:evidence_quote] = "do you prefer hiking"

    parsed = described_class.parse(
      text: { candidates: [ candidate ] }.to_json,
      allowed_message_ids: [ 12 ], allowed_memory_ids: [],
      source_message_texts: { 12 => "By the way, do you prefer hiking?" }
    )

    expect(parsed).to be_empty
  end

  it "rejects a narrated scene action as durable evidence" do
    candidate[:kind] = "preference"
    candidate[:content] = "Alex prefers opening windows"
    candidate[:evidence_quote] = "I open the window"

    parsed = described_class.parse(
      text: { candidates: [ candidate ] }.to_json,
      allowed_message_ids: [ 12 ], allowed_memory_ids: [],
      source_message_texts: { 12 => "*I open the window*" }
    )

    expect(parsed).to be_empty
  end

  it "accepts an explicit preference followed by a question" do
    candidate[:kind] = "preference"
    candidate[:content] = "Alex likes black coffee"
    candidate[:evidence_quote] = "I like black coffee"

    parsed = described_class.parse(
      text: { candidates: [ candidate ] }.to_json,
      allowed_message_ids: [ 12 ], allowed_memory_ids: [],
      source_message_texts: { 12 => "I like black coffee, and you?" }
    )

    expect(parsed.first.fetch("evidence_quote")).to eq("I like black coffee")
  end

  it "does not assign a character question to the user in a mixed message" do
    valid = candidate.merge(kind: "preference", content: "Alex likes black coffee",
                            evidence_quote: "I like black coffee")
    wrong_owner = candidate.merge(kind: "preference", content: "Alex likes cocoa",
                                  evidence_quote: "do you like cocoa")

    parsed = described_class.parse(
      text: { candidates: [ valid, wrong_owner ] }.to_json,
      allowed_message_ids: [ 12 ], allowed_memory_ids: [],
      source_message_texts: { 12 => "I like black coffee. Do you like cocoa?" }
    )

    expect(parsed.map { |item| item.fetch("content") }).to eq([ "Alex likes black coffee" ])
  end

  it "retains a user preference involving the character" do
    candidate[:kind] = "preference"
    candidate[:content] = "Alex likes when Nora describes her feelings"
    candidate[:evidence_quote] = "I like when you describe your feelings"

    parsed = described_class.parse(
      text: { candidates: [ candidate ] }.to_json,
      allowed_message_ids: [ 12 ], allowed_memory_ids: [],
      source_message_texts: { 12 => "I like when you describe your feelings" }
    )

    expect(parsed.size).to eq(1)
  end

  it "keeps a supported statement when another candidate cites a scene action" do
    valid = candidate.merge(evidence_quote: "I like black coffee", content: "Alex likes black coffee")
    scene = candidate.merge(evidence_quote: "I open the window",
                            content: "Alex prefers opening windows")

    parsed = described_class.parse(
      text: { candidates: [ valid, scene ] }.to_json,
      allowed_message_ids: [ 12 ], allowed_memory_ids: [],
      source_message_texts: { 12 => "I like black coffee. *I open the window*" }
    )

    expect(parsed.map { |item| item.fetch("content") }).to eq([ "Alex likes black coffee" ])
  end
end
