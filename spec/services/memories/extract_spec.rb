require "rails_helper"
require_relative "../../support/ai/fake_adapter"

RSpec.describe Memories::Extract do
  let(:now) { Time.zone.parse("2026-09-22 12:00:00") }
  let(:personality) { create(:personality, :active) }
  let(:thread) { create(:conversation_thread, personality: personality) }
  let(:user_message) do
    create(
      :message,
      conversation_thread: thread,
      personality_version: personality.current_version,
      position: 3,
      content: "I am moving to Denver on Friday"
    )
  end
  let(:assistant_message) do
    create(
      :message,
      :assistant,
      conversation_thread: thread,
      personality_version: personality.current_version,
      position: 4,
      content: "That is a big step."
    )
  end
  let(:generation_run) do
    create(
      :generation_run,
      conversation_thread: thread,
      personality_version: personality.current_version,
      user_message: user_message,
      assistant_message: assistant_message,
      status: :completed,
      completed_at: now
    )
  end
  let(:extraction) { create(:memory_extraction, personality: personality, generation_run: generation_run) }
  let(:adapter) { Ai::FakeAdapter.new }
  let(:gateway) { Ai::Gateway.new(adapter: adapter) }

  before do
    create(
      :model_price,
      provider: "mistral",
      model: personality.utility_model,
      effective_from: now - 1.day
    )
  end

  it "stores validated memories, provenance, usage, and the structured request" do
    adapter.enqueue_response(
      text: {
        candidates: [
          {
            action: "create",
            kind: "fact",
            content: "The user is moving to Denver",
            evidence_quote: "I am moving to Denver",
            importance: 85,
            occurred_at: "2026-09-25T09:00:00+05:00",
            source_message_ids: [ user_message.id ],
            existing_memory_id: nil,
            sensitivity: "normal"
          }
        ]
      }.to_json,
      request_id: "memory-request",
      model: personality.utility_model,
      usage: Ai::Usage.new(input_tokens: 100, output_tokens: 40)
    )

    result = described_class.call(
      extraction: extraction,
      gateway: gateway,
      now: now,
      clock: -> { 1.0 }
    )

    expect(result.status).to eq(:completed)
    expect(result.memories.first).to have_attributes(
      content: "The user is moving to Denver",
      importance: 85,
      status: "active"
    )
    expect(result.memories.first.source_messages).to contain_exactly(user_message)
    expect(extraction.reload).to have_attributes(status: "completed", completed_at: now)
    expect(extraction.model_call).to have_attributes(
      purpose: "memory_extraction",
      provider_request_id: "memory-request"
    )
    expect(adapter.requests.first).to include(
      model: personality.utility_model,
      response_schema: Memories::Extraction::Schema::RESPONSE_SCHEMA,
      temperature: 0.1,
      max_output_tokens: 2_500
    )
  end

  it "rejects provenance from an earlier context message" do
    previous_message = create(
      :message,
      conversation_thread: thread,
      personality_version: personality.current_version,
      position: 1,
      content: "I enjoy visiting museums, but I need an invitation"
    )
    adapter.enqueue_response(
      text: {
        candidates: [
          {
            action: "create",
            kind: "preference",
            content: "The user enjoys visiting museums when invited",
            evidence_quote: "I enjoy visiting museums",
            importance: 75,
            occurred_at: nil,
            source_message_ids: [ previous_message.id ],
            existing_memory_id: nil,
            sensitivity: "normal"
          }
        ]
      }.to_json,
      request_id: "recent-memory-request",
      model: personality.utility_model,
      usage: Ai::Usage.new(input_tokens: 100, output_tokens: 40)
    )

    result = described_class.call(extraction: extraction, gateway: gateway, now: now)

    expect(result.status).to eq(:failed)
    expect(result.error_code).to eq("invalid_output")
    expect(personality.memories).to be_empty
  end

  it "fails safely when the provider output violates the local schema" do
    adapter.enqueue_response(
      text: '{"candidates":[{"content":"missing fields"}]}',
      request_id: "invalid-memory",
      model: personality.utility_model,
      usage: Ai::Usage.new(input_tokens: 10, output_tokens: 5)
    )

    result = described_class.call(extraction: extraction, gateway: gateway, now: now)

    expect(result.error_code).to eq("invalid_output")
    expect(extraction.reload).to have_attributes(status: "failed", error_code: "invalid_output")
    expect(personality.memories).to be_empty
  end

  it "is idempotent after a completed extraction" do
    extraction.update!(status: :completed, completed_at: now)

    result = described_class.call(extraction: extraction, gateway: gateway, now: now)

    expect(result.status).to eq(:skipped)
    expect(adapter.requests).to be_empty
  end

  it "can reclaim a stale running extraction after a worker crash" do
    extraction.update!(status: :running, started_at: now - 20.minutes)
    adapter.enqueue_response(
      text: '{"candidates":[]}',
      request_id: "reclaimed-memory",
      model: personality.utility_model,
      usage: Ai::Usage.new(input_tokens: 10, output_tokens: 2)
    )

    result = described_class.call(extraction: extraction, gateway: gateway, now: now)

    expect(result.status).to eq(:completed)
    expect(extraction.reload.attempts_count).to eq(1)
  end
end
