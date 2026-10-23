require "rails_helper"
require_relative "../../support/ai/fake_adapter"

RSpec.describe Relationships::Update do
  let(:now) { Time.zone.parse("2026-09-22 13:00:00") }
  let(:personality) { create(:personality, :active) }
  let(:thread) { create(:conversation_thread, personality: personality) }
  let(:user_message) do
    create(:message, conversation_thread: thread, position: 1,
           content: I18n.t("app.flash.signed_in", locale: :ru), language: "ru")
  end
  let(:assistant_message) do
    create(:message, :assistant, conversation_thread: thread, position: 2, content: "That matters to me.")
  end
  let(:generation_run) do
    create(:generation_run, conversation_thread: thread, personality_version: personality.current_version,
           user_message: user_message, assistant_message: assistant_message, status: :completed, completed_at: now)
  end
  let(:adapter) { Ai::FakeAdapter.new }
  let(:gateway) { Ai::Gateway.new(adapter: adapter) }

  before do
    create(:model_price, provider: "mistral", model: personality.utility_model, version: "2026-09",
           input_microusd_per_million: 1, cached_input_microusd_per_million: 1,
           output_microusd_per_million: 1, effective_from: now - 1.day)
  end

  it "updates personality-wide relationship state and keeps a grounded revision" do
    adapter.enqueue_response(
      text: { status: "changed", summary: "They trust each other more now.",
              source_message_ids: [ user_message.id, assistant_message.id ],
              durable_evidence_quote: user_message.content }.to_json,
      request_id: "relationship-1", usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )
    adapter.enqueue_response(
      text: '{"valid":true,"violations":[]}', request_id: "relationship-scope-1",
      usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )

    result = described_class.call(generation_run: generation_run, gateway: gateway, now: now)

    expect(result).to be_success
    expect(personality.reload.relationship_state).to have_attributes(
      summary: "They trust each other more now.", revision: 1
    )
    expect(result.version).to have_attributes(
      generation_run_id: generation_run.id,
      source_message_ids: [ user_message.id, assistant_message.id ],
      reason: "model_update"
    )
    expect(result.version.model_call).to be_memory_consolidation
    expect(generation_run.reload.relationship_update_processed_at).to be_present
    expect(adapter.requests.first.fetch(:input).first.fetch(:content)).to include("Write the entire summary in Russian")
    scope_input = adapter.requests.second.fetch(:input)
    expect(scope_input.first.fetch(:content)).to eq(Ai::PromptCatalog.content("relationship_scope_check"))
    expect(scope_input.last.fetch(:content)).to include("previous_relationship_state")

    expect { described_class.call(generation_run: generation_run, gateway: gateway, now: now) }
      .not_to change(ModelCall, :count)
  end

  it "requests Russian even when the previous relationship state is in English" do
    personality.create_relationship_state!(summary: "Trust is growing.", revision: 1)
    adapter.enqueue_response(
      text: { status: "changed", summary: "Trust is growing.",
              source_message_ids: [ user_message.id, assistant_message.id ],
              durable_evidence_quote: user_message.content }.to_json,
      request_id: "relationship-russian", usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )
    adapter.enqueue_response(
      text: '{"valid":true,"violations":[]}', request_id: "relationship-russian-scope",
      usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )

    described_class.call(generation_run: generation_run, gateway: gateway, now: now)

    input = adapter.requests.first.fetch(:input)
    expect(input.first.fetch(:content)).to include("Write the entire summary in Russian")
    expect(input.last.fetch(:content)).to include("Trust is growing.")
  end

  it "requests English for an English user message" do
    user_message.update!(content: "I trust you now", language: "en")
    adapter.enqueue_response(
      text: %({"status":"changed","summary":"Trust between them is growing.","source_message_ids":[#{user_message.id},#{assistant_message.id}],"durable_evidence_quote":"I trust you now"}),
      request_id: "relationship-english", usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )
    adapter.enqueue_response(
      text: '{"valid":true,"violations":[]}', request_id: "relationship-english-scope",
      usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )

    described_class.call(generation_run: generation_run, gateway: gateway, now: now)

    expect(adapter.requests.first.fetch(:input).first.fetch(:content)).to include("Write the entire summary in English")
  end

  it "records an unchanged turn without creating a relationship version or repeating the model call" do
    state = personality.create_relationship_state!(summary: "They speak informally.", revision: 1)
    adapter.enqueue_response(
      text: '{"status":"unchanged","summary":"They speak informally.","source_message_ids":[],"durable_evidence_quote":null}',
      request_id: "relationship-unchanged", usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )

    result = described_class.call(generation_run: generation_run, gateway: gateway, now: now)

    expect(result).to be_success
    expect(result.version).to be_nil
    expect(state.reload.revision).to eq(1)
    expect(state.versions).to be_empty
    expect(generation_run.reload.relationship_update_processed_at).to be_present
    expect { described_class.call(generation_run: generation_run, gateway: gateway, now: now) }
      .not_to change(ModelCall, :count)
  end

  it "does not replace relationship state with a description of the latest scene" do
    user_message.update!(content: "Yes\n*I wave from the doorway*", language: "en")
    assistant_message.update!(content: "I wave back. See you soon.")
    state = personality.create_relationship_state!(summary: "They speak openly.", revision: 1)
    adapter.enqueue_response(
      text: { status: "changed", summary: "The character waves back and says goodbye.",
              source_message_ids: [ user_message.id, assistant_message.id ],
              durable_evidence_quote: "I wave from the doorway" }.to_json,
      request_id: "relationship-scene", usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )

    result = described_class.call(generation_run: generation_run, gateway: gateway, now: now)

    expect(result).to be_success
    expect(result.version).to be_nil
    expect(state.reload).to have_attributes(summary: "They speak openly.", revision: 1)
    expect(adapter.requests.size).to eq(1)
    expect(generation_run.reload.relationship_update_processed_at).to be_present
  end

  it "can clean an unsupported prior state without citing the current turn" do
    state = personality.create_relationship_state!(summary: "The character manages the user's schedule.", revision: 1)
    adapter.enqueue_response(
      text: '{"status":"cleanup","summary":"","source_message_ids":[],"durable_evidence_quote":null}',
      request_id: "relationship-cleanup", usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )

    result = described_class.call(generation_run: generation_run, gateway: gateway, now: now)

    expect(result).to be_success
    expect(result.version).to have_attributes(reason: "cleanup", source_message_ids: [], summary: "")
    expect(state.reload).to have_attributes(summary: "", revision: 2)
  end

  it "does not save a relationship claim rejected by the independent scope check" do
    adapter.enqueue_response(
      text: { status: "changed", summary: "The character manages the user's schedule.",
              source_message_ids: [ user_message.id ],
              durable_evidence_quote: user_message.content }.to_json,
      request_id: "relationship-bad", usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )
    adapter.enqueue_response(
      text: '{"valid":false,"violations":["Unsupported claim"]}', request_id: "relationship-bad-scope",
      usage: Ai::Usage.new(input_tokens: 20, output_tokens: 8)
    )

    result = described_class.call(generation_run: generation_run, gateway: gateway, now: now)

    expect(result.error_code).to eq("scope_violation")
    expect(personality.relationship_state.reload.summary).to eq("")
    expect(generation_run.reload.relationship_update_processed_at).to be_nil
  end
end
