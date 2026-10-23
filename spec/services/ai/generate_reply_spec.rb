require "rails_helper"
require_relative "../../support/ai/fake_adapter"

RSpec.describe Ai::GenerateReply do
  subject(:result) do
    described_class.call(
      generation_run: generation_run,
      gateway: gateway,
      now: now,
      clock: -> { 1.0 }
    )
  end

  let(:now) { Time.zone.parse("2026-09-19 15:00:00") }
  let(:personality) { create(:personality, :active) }
  let(:thread) { create(:conversation_thread, personality: personality) }
  let(:user_message) do
    create(
      :message,
      conversation_thread: thread,
      personality_version: personality.current_version,
      position: 1,
      content: "Hello"
    )
  end
  let(:assistant_message) do
    create(
      :message,
      conversation_thread: thread,
      personality_version: personality.current_version,
      position: 2,
      role: :assistant,
      status: :streaming,
      content: "",
      client_token: nil
    )
  end
  let(:generation_run) do
    create(
      :generation_run,
      conversation_thread: thread,
      personality_version: personality.current_version,
      user_message: user_message,
      assistant_message: assistant_message
    )
  end
  let(:adapter) { Ai::FakeAdapter.new }
  let(:gateway) { Ai::Gateway.new(adapter: adapter) }

  before do
    create(
      :model_price,
      provider: "mistral",
      model: personality.conversation_model,
      version: "2026-09",
      input_microusd_per_million: 2_500_000,
      cached_input_microusd_per_million: 1_250_000,
      output_microusd_per_million: 10_000_000,
      effective_from: now - 1.day
    )
  end

  it "streams and persists the assistant reply with usage" do
    adapter.enqueue_stream(
      deltas: [ "Hello", "!" ],
      text: "Hello!",
      request_id: "req_stream",
      usage: Ai::Usage.new(input_tokens: 20, cached_input_tokens: 10, output_tokens: 3)
    )

    expect(result).to be_success
    expect(assistant_message.reload).to have_attributes(
      content: "Hello!",
      status: "completed",
      language: "en"
    )
    expect(generation_run.reload).to have_attributes(status: "completed", completed_at: now)
    expect(generation_run.model_calls.last).to have_attributes(
      status: "completed",
      provider_request_id: "req_stream",
      input_tokens: 20,
      cached_input_tokens: 10,
      output_tokens: 3
    )
    expect(adapter.requests.first).to include(
      model: personality.conversation_model,
      prompt_cache_key: "facet-conversation-thread-#{thread.id}-mistral-" \
        "pv-#{personality.current_version.id}-pp-none-ar-" \
        "#{Digest::SHA256.hexdigest(Ai::PromptCatalog.content('application_rules')).first(12)}-" \
        "summary-none-v8"
    )
  end

  it "persists a safe failure on the run and assistant placeholder" do
    image = assistant_message.create_message_image!(
      source_avatar_object_key: "personalities/#{personality.id}/avatars/current.jpg"
    )
    adapter.enqueue_error(Ai::TimeoutError.new("private provider detail"))

    expect(result).not_to be_success
    expect(generation_run.reload).to have_attributes(
      status: "failed",
      error_code: "timeout",
      error_message: "Model request timed out"
    )
    expect(assistant_message.reload).to be_failed
    expect(image.reload).to have_attributes(status: "failed", error_code: "timeout")
  end

  it "does not issue a duplicate model call for a terminal run" do
    generation_run.update!(status: :completed, completed_at: now)

    expect(result).not_to be_success
    expect(result.error_code).to eq("already_completed")
    expect(adapter.requests).to be_empty
    expect(ModelCall.count).to eq(0)
    expect(generation_run.reload).to be_completed
    expect(assistant_message.reload).to be_streaming
  end

  it "publishes and dispatches photo generation after the reply commits" do
    image = assistant_message.create_message_image!(
      source_avatar_object_key: "personalities/#{personality.id}/avatars/current.jpg"
    )
    adapter.enqueue_stream(
      deltas: [ "Here you go." ],
      text: "Here you go.",
      request_id: "req-with-photo",
      usage: Ai::Usage.new(input_tokens: 10, output_tokens: 2)
    )
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect do
      expect { result }
        .to have_enqueued_job(Ai::GenerateMessageImageJob).with(image.id).once
        .and have_enqueued_job(Ai::MemoryExtractionJob).once
          .and have_enqueued_job(Ai::RelationshipUpdateJob).once
    end.to change(OutboxEvent, :count).by(3)

    expect(OutboxEvent.last).to have_attributes(
      status: "dispatched"
    )
    expect(OutboxEvent.find_by!(event_key: "generate-message-image:#{image.id}")).to be_dispatched
  end

  it "does not disturb a run already owned by another worker" do
    generation_run.update!(status: :running, started_at: now)

    expect(result).not_to be_success
    expect(result.error_code).to eq("already_running")
    expect(adapter.requests).to be_empty
    expect(generation_run.reload).to be_running
    expect(assistant_message.reload).to be_streaming
  end

  it "does not enqueue extraction when automatic memory is disabled" do
    personality.update!(automatic_memory_enabled: false)
    adapter.enqueue_stream(
      deltas: [ "Hello!" ],
      text: "Hello!",
      request_id: "req-no-memory",
      usage: Ai::Usage.new(input_tokens: 10, output_tokens: 2)
    )

    expect { result }.not_to have_enqueued_job(Ai::MemoryExtractionJob)
    expect(generation_run.reload.memory_extraction).to be_nil
  end

  it "cooperatively stops between provider chunks and preserves partial text" do
    adapter.enqueue_stream(
      deltas: [ "First", " second" ],
      text: "First second",
      request_id: "req_stopped",
      usage: Ai::Usage.new(input_tokens: 10, output_tokens: 2),
      after_delta: lambda do |_delta, index|
        GenerationRuns::Stop.call(generation_run: generation_run, now: now) if index.zero?
      end
    )

    expect(result).not_to be_success
    expect(result.error_code).to eq("stopped")
    expect(generation_run.reload).to be_stopped
    expect(assistant_message.reload).to have_attributes(status: "stopped", content: "First")
  end

  it "retrieves cross-thread memory and records why it was recalled" do
    memory = create(:memory, personality: personality, content: "The user prefers green tea", importance: 70)
    deleted = create(:memory, personality: personality, content: "The user prefers black tea",
                     status: :deleted, deleted_at: now)
    personality.create_relationship_state!(summary: "They speak warmly.", revision: 1)
    user_message.update!(content: "Which tea should I order?", language: "ru")
    adapter.enqueue_stream(
      deltas: [ "Green." ], text: "Green.", request_id: "req-memory",
      usage: Ai::Usage.new(input_tokens: 20, output_tokens: 3)
    )

    expect(result).to be_success
    prompt_text = adapter.requests.first.fetch(:input).map { |item| item.content.to_s }.join("\n")
    manifest = generation_run.reload.prompt_manifest

    expect(prompt_text).to include(memory.content, "They speak warmly.")
    expect(prompt_text).not_to include(deleted.content)
    expect(manifest.fetch("memory_ids")).to eq([ memory.id ])
    expect(manifest.fetch("memory_retrieval").first).to include("memory_id" => memory.id, "rank" => 1)
    expect(memory.reload.last_recalled_at).to eq(now)
    expect(deleted.reload.last_recalled_at).to be_nil
  end
end
