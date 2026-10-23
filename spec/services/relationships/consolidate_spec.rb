require "rails_helper"
require_relative "../../support/ai/fake_adapter"

RSpec.describe Relationships::Consolidate do
  let(:now) { Time.zone.parse("2026-09-25 13:00:00") }
  let(:personality) { create(:personality, :active) }
  let(:thread) { create(:conversation_thread, personality: personality) }
  let(:source_user) { create(:message, conversation_thread: thread, position: 1, content: "Let's speak informally") }
  let(:source_assistant) do
    create(:message, :assistant, conversation_thread: thread, position: 2, content: "Agreed to speak informally")
  end
  let(:user_message) { create(:message, conversation_thread: thread, position: 3, content: "Hello") }
  let(:assistant_message) { create(:message, :assistant, conversation_thread: thread, position: 4, content: "Hello") }
  let(:generation_run) do
    create(:generation_run, conversation_thread: thread, personality_version: personality.current_version,
           user_message: user_message, assistant_message: assistant_message, status: :completed,
           relationship_update_processed_at: now)
  end
  let(:state) do
    personality.create_relationship_state!(
      summary: "They speak informally. The user needs a plan made for them.", revision: 1
    )
  end
  let(:adapter) { Ai::FakeAdapter.new }
  let(:gateway) { Ai::Gateway.new(adapter: adapter) }

  before do
    create(:model_price, provider: "mistral", model: personality.utility_model, version: "2026-09",
           input_microusd_per_million: 1, cached_input_microusd_per_million: 1,
           output_microusd_per_million: 1, effective_from: now - 1.day)
    state.versions.create!(revision: 1, summary: state.summary,
                           source_message_ids: [ source_user.id, source_assistant.id ], reason: :model_update)
  end

  it "reviews cited original messages and removes out-of-scope content" do
    adapter.enqueue_response(
      text: '{"status":"cleanup","summary":"They speak informally.","source_message_ids":[]}',
      request_id: "relationship-audit", usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )
    adapter.enqueue_response(
      text: '{"valid":true,"violations":[]}', request_id: "relationship-audit-scope",
      usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )

    result = described_class.call(generation_run: generation_run, gateway: gateway, now: now)

    expect(result).to be_success
    expect(result.version).to have_attributes(reason: "consolidation", summary: "They speak informally.")
    expect(state.reload).to have_attributes(summary: "They speak informally.", revision: 2,
                                            last_consolidated_message_id: source_assistant.id)
    expect(generation_run.reload.relationship_consolidated_at).to be_present
    payload = adapter.requests.first.fetch(:input).last.fetch(:content)
    expect(payload).to include("Let's speak informally", "Agreed to speak informally")
    expect(payload).not_to include("Hello")
    expect { described_class.call(generation_run: generation_run, gateway: gateway, now: now) }
      .not_to change(ModelCall, :count)
  end

  it "moves through historical evidence in bounded batches" do
    stub_const("Relationships::Consolidate::MAX_EVIDENCE_CHARS", source_user.content.length + 1)
    unchanged = {
      status: "unchanged", summary: state.summary, source_message_ids: []
    }.to_json
    2.times do |index|
      adapter.enqueue_response(
        text: unchanged, request_id: "relationship-batch-#{index}",
        usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
      )
    end

    described_class.call(generation_run: generation_run, gateway: gateway, now: now)
    expect(state.reload.last_consolidated_message_id).to eq(source_user.id)
    first_payload = adapter.requests.first.fetch(:input).last.fetch(:content)
    expect(first_payload).to include(source_user.content)
    expect(first_payload).not_to include(source_assistant.content)

    next_user = create(:message, conversation_thread: thread, position: 5, content: "Another question")
    next_assistant = create(:message, :assistant, conversation_thread: thread, position: 6, content: "I am listening")
    next_run = create(:generation_run, conversation_thread: thread,
                      personality_version: personality.current_version,
                      user_message: next_user, assistant_message: next_assistant,
                      status: :completed, relationship_update_processed_at: now)
    described_class.call(generation_run: next_run, gateway: gateway, now: now)

    expect(state.reload.last_consolidated_message_id).to eq(source_assistant.id)
    second_payload = adapter.requests.last.fetch(:input).last.fetch(:content)
    expect(second_payload).to include(source_assistant.content)
    expect(second_payload).not_to include(source_user.content)
  end
end
