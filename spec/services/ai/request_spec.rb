require "rails_helper"
require_relative "../../support/ai/fake_adapter"

RSpec.describe Ai::Request do
  subject(:result) do
    described_class.call(
      user: user,
      personality: personality,
      generation_run: generation_run,
      purpose: :conversation,
      provider: "mistral",
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
    expect(result.model_call.reserved_cost_microusd).to eq(0)
    expect(result.model_call.reservation_expires_at).to be_nil
    expect(result.model_call.latency_ms).to eq(0)
    ModelPrice.find_by!(provider: "mistral", model: "mistral-large-2512").update!(
      output_microusd_per_million: 20_000_000
    )
    expect(result.model_call.reload.cost_microusd).to eq(3_250)
  end

  it "records time to first streamed token without storing prompt text in telemetry" do
    adapter.enqueue_stream(deltas: [ "Hello" ], text: "Hello", request_id: "req_stream",
                           usage: Ai::Usage.new(input_tokens: 10, cached_input_tokens: 0, output_tokens: 1))
    times = [ 1.0, 1.25, 1.5 ]
    streamed = described_class.call(
      user: user, personality: personality, generation_run: generation_run,
      purpose: :conversation, provider: "mistral", model: "mistral-large-2512",
      input: "private prompt", gateway: gateway, now: now,
      clock: -> { times.shift }, stream: true
    )

    expect(streamed).to be_success
    expect(generation_run.reload.prompt_manifest["first_token_latency_ms"]).to eq(250)
  end

  it "records normalized timeout failures without storing the prompt" do
    adapter.enqueue_error(Ai::TimeoutError.new("secret provider detail"))

    expect(result).not_to be_success
    expect(result.error_code).to eq("timeout")
    expect(result.model_call).to have_attributes(status: "failed", error_class: "Ai::TimeoutError")
    expect(result.model_call.error_message).not_to include("secret provider detail")
    expect(ModelCall.column_names).not_to include("prompt")
    expect(result.model_call.reserved_cost_microusd).to eq(0)
  end

  it "emits a budget rejection without sending the prompt" do
    user.update!(monthly_ai_limit_microusd: 0)
    emitted = []
    allow(Operations::Telemetry).to receive(:emit) do |event, **attributes|
      emitted << [ event, attributes ]
    end

    expect(result.error_code).to eq("budget_exceeded")
    expect(adapter.requests).to be_empty
    expect(emitted).to include([ "budget_rejection",
                                hash_including(error_code: "budget_exceeded", model: "mistral-large-2512") ])
    expect(emitted.flatten.join).not_to include("private prompt")
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
      provider: "mistral",
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

  it "uses the selected provider's model for an existing personality" do
    create(:model_price, provider: "openai", model: "gpt-4o-2024-11-20", effective_from: now - 1.day)
    adapter.enqueue_response(
      text: "Hello", request_id: "req_openai",
      usage: Ai::Usage.new(input_tokens: 10, cached_input_tokens: 0, output_tokens: 2)
    )

    switched = described_class.call(
      user: user, personality: personality, purpose: :conversation,
      model: "mistral-large-2512", input: "Hi", provider: "openai",
      gateway: gateway, now: now, clock: -> { 1.0 }
    )

    expect(switched).to be_success
    expect(switched.model_call).to have_attributes(provider: "openai", model: "gpt-4o-2024-11-20")
    expect(adapter.requests.first).to include(model: "gpt-4o-2024-11-20")
  end

  it "uses the conversation model for initiative messages after a provider switch" do
    create(:model_price, provider: "openai", model: "gpt-4o-2024-11-20", effective_from: now - 1.day)
    adapter.enqueue_response(text: "Hello", request_id: "initiative-openai",
                             usage: Ai::Usage.new(input_tokens: 10, output_tokens: 2))

    switched = described_class.call(
      user: user, personality: personality, purpose: :initiative, model_role: :conversation,
      model: "mistral-large-2512", input: "Hi", provider: "openai",
      gateway: gateway, now: now, clock: -> { 1.0 }
    )

    expect(switched).to be_success
    expect(switched.model_call).to have_attributes(purpose: "initiative", model: "gpt-4o-2024-11-20")
  end

  it "blocks a request before contacting the provider when the user limit is exhausted" do
    user.update!(monthly_ai_limit_microusd: 1)

    expect(result).not_to be_success
    expect(result.error_code).to eq("budget_exceeded")
    expect(adapter.requests).to be_empty
    expect(ModelCall.count).to eq(0)
  end

  it "blocks a request when the application emergency limit is exhausted" do
    allow(Ai::SpendingBudget).to receive(:global_limit).and_return(1)

    expect(result.error_code).to eq("budget_exceeded")
    expect(adapter.requests).to be_empty
  end

  it "releases a reservation after a provider failure with partial usage" do
    user.update!(monthly_ai_limit_microusd: 50_000)
    adapter.enqueue_error(Ai::ProviderError.new("detail", usage: Ai::Usage.new(input_tokens: 100, output_tokens: 2)))

    expect(result.model_call).to have_attributes(status: "failed", reserved_cost_microusd: 0)
    expect(Ai::SpendingBudget.snapshot(user: user, now: now)).to have_attributes(spent: 270, reserved: 0)
  end
end
