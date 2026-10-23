require "rails_helper"
require_relative "../../support/ai/fake_adapter"

RSpec.describe ConversationThreads::Summarize do
  let(:now) { Time.zone.parse("2026-09-22 12:00:00") }
  let(:personality) { create(:personality, :active) }
  let(:thread) { create(:conversation_thread, personality: personality) }
  let(:user_message) { create(:message, conversation_thread: thread, position: 1, content: "We are visiting the museum on Friday") }
  let(:assistant_message) do
    create(:message, :assistant, conversation_thread: thread, position: 2, content: "I will look forward to Friday")
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

  it "stores an incremental summary, boundary, provenance and immutable version" do
    adapter.enqueue_response(
      text: %({"summary":"They agreed to visit the museum on Friday.","source_message_ids":[#{user_message.id},#{assistant_message.id}]}),
      request_id: "summary-1", usage: Ai::Usage.new(input_tokens: 20, output_tokens: 10)
    )

    result = described_class.call(generation_run: generation_run, gateway: gateway, now: now)

    expect(result).to be_success
    expect(thread.reload).to have_attributes(
      summary: "They agreed to visit the museum on Friday.",
      summary_through_message_id: assistant_message.id
    )
    expect(result.version).to have_attributes(
      revision: 1, source_message_ids: [ user_message.id, assistant_message.id ]
    )
    expect(result.version.model_call).to be_thread_summary

    expect { described_class.call(generation_run: generation_run, gateway: gateway, now: now) }
      .not_to change(ModelCall, :count)
  end

  it "rejects unsupported provenance without moving the summary boundary" do
    adapter.enqueue_response(
      text: '{"summary":"Invented fact.","source_message_ids":[999999]}',
      request_id: "summary-bad", usage: Ai::Usage.new(input_tokens: 20, output_tokens: 10)
    )

    result = described_class.call(generation_run: generation_run, gateway: gateway, now: now)

    expect(result.error_code).to eq("invalid_output")
    expect(thread.reload.summary_through_message_id).to be_nil
    expect(thread.summary_versions).to be_empty
  end

  it "uses only messages after the previous summary boundary" do
    prior_run = generation_run
    prior_version = thread.summary_versions.create!(
      generation_run: prior_run, through_message: assistant_message, revision: 1,
      summary: "They previously agreed on the museum.", source_message_ids: [ user_message.id, assistant_message.id ]
    )
    thread.update!(summary: prior_version.summary, summary_through_message: assistant_message)
    next_user = create(:message, conversation_thread: thread, position: 3, content: "We will buy tickets online")
    next_assistant = create(:message, :assistant, conversation_thread: thread, position: 4, content: "Good idea")
    next_run = create(:generation_run, conversation_thread: thread, personality_version: personality.current_version,
                      user_message: next_user, assistant_message: next_assistant, status: :completed, completed_at: now)
    adapter.enqueue_response(
      text: %({"summary":"They are visiting the museum and will buy tickets online.","source_message_ids":[#{next_user.id},#{next_assistant.id}]}),
      request_id: "summary-2", usage: Ai::Usage.new(input_tokens: 20, output_tokens: 10)
    )

    result = described_class.call(generation_run: next_run, gateway: gateway, now: now)
    payload = adapter.requests.last.fetch(:input).last.fetch(:content)

    expect(result.version).to have_attributes(revision: 2, previous_version_id: prior_version.id)
    expect(payload).to include("They previously agreed on the museum", "We will buy tickets online")
    expect(payload).not_to include("We are visiting the museum on Friday")
  end
end
