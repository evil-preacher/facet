require "rails_helper"
require_relative "../../support/ai/fake_adapter"

RSpec.describe Ai::Request do
  subject(:result) do
    described_class.call(
      user: user,
      personality: personality,
      generation_run: generation_run,
      purpose: :conversation,
      model: "mistral-large-2512",
      input: "private prompt",
      gateway: gateway,
      now: now,
      clock: -> { 1.0 }
    )
  end

  let(:now) { Time.zone.parse("2026-09-19 12:00:00") }
  let(:personality) { create(:personality, :active) }
  let(:user) { personality.user }
  let(:generation_run) { create(:generation_run, conversation_thread: create(:conversation_thread, personality: personality)) }
  let(:adapter) { Ai::FakeAdapter.new }
  let(:gateway) { Ai::Gateway.new(adapter: adapter) }

  before do
    create(
      :model_price,
      provider: "mistral",
      model: "mistral-large-2512",
      version: "2026-09",
      input_microusd_per_million: 2_500_000,
      cached_input_microusd_per_million: 1_250_000,
      output_microusd_per_million: 10_000_000,
      effective_from: now - 1.day
    )
  end

  it "persists provider usage and immutable calculated cost" do
    adapter.enqueue_response(
      text: "Hello",
      request_id: "req_123",
      usage: Ai::Usage.new(input_tokens: 1_000, cached_input_tokens: 200, output_tokens: 100)
    )

    expect(result).to be_success
    expect(result.response.text).to eq("Hello")
    expect(result.model_call).to have_attributes(
      user: user,
      personality: personality,
      generation_run: generation_run,
      purpose: "conversation",
      provider: "mistral",
      model: "mistral-large-2512",
      response_model: "mistral-large-2512",
      provider_request_id: "req_123",
      status: "completed",
      input_tokens: 1_000,
      cached_input_tokens: 200,
      output_tokens: 100,
      cost_microusd: 3_250,
      pricing_version: "2026-09"
    )
    expect(result.model_call.latency_ms).to eq(0)
  end

  it "records normalized timeout failures without storing the prompt" do
    adapter.enqueue_error(Ai::TimeoutError.new("secret provider detail"))

    expect(result).not_to be_success
    expect(result.error_code).to eq("timeout")
    expect(result.model_call).to have_attributes(status: "failed", error_class: "Ai::TimeoutError")
    expect(result.model_call.error_message).not_to include("secret provider detail")
    expect(ModelCall.column_names).not_to include("prompt")
  end

  it "records rate limits with a stable code" do
    adapter.enqueue_error(Ai::RateLimitError.new("provider detail"))

    expect(result).not_to be_success
    expect(result.error_code).to eq("rate_limit")
  end

  it "persists usage returned with a partial provider failure" do
    usage = Ai::Usage.new(input_tokens: 100, cached_input_tokens: 20, output_tokens: 10)
    adapter.enqueue_error(Ai::ProviderError.new("detail", request_id: "req_partial", usage: usage))

    expect(result).not_to be_success
    expect(result.model_call).to have_attributes(
      provider_request_id: "req_partial",
      input_tokens: 100,
      cached_input_tokens: 20,
      output_tokens: 10,
      cost_microusd: 325,
      pricing_version: "2026-09"
    )
  end

  it "does not call the provider again for a completed generation run" do
    generation_run.update!(status: :completed, completed_at: now)

    expect(result).not_to be_success
    expect(result.error_code).to eq("already_completed")
    expect(adapter.requests).to be_empty
    expect(ModelCall.count).to eq(0)
  end

  it "passes the prompt cache key through the gateway" do
    adapter.enqueue_response(
      text: "Hello",
      request_id: "req_cache",
      usage: Ai::Usage.new(input_tokens: 10, cached_input_tokens: 0, output_tokens: 2)
    )

    cached_result = described_class.call(
      user: user,
      personality: personality,
      generation_run: generation_run,
      purpose: :conversation,
      model: "mistral-large-2512",
      input: "private prompt",
      prompt_cache_key: "facet-pv-1",
      gateway: gateway,
      now: now,
      clock: -> { 1.0 }
    )

    expect(cached_result).to be_success
    expect(adapter.requests.first).to include(prompt_cache_key: "facet-pv-1")
  end

  it "rejects a generation run from another personality before calling the provider" do
    other_run = create(:generation_run)

    rejected = described_class.call(
      user: user,
      personality: personality,
      generation_run: other_run,
      purpose: :conversation,
      model: "mistral-large-2512",
      input: "private prompt",
      gateway: gateway
    )

    expect(rejected.error_code).to eq("invalid_context")
    expect(adapter.requests).to be_empty
    expect(ModelCall.count).to eq(0)
  end
end
