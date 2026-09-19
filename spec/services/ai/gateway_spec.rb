require "rails_helper"
require_relative "../../support/ai/fake_adapter"

RSpec.describe Ai::Gateway do
  let(:usage) { Ai::Usage.new(input_tokens: 12, cached_input_tokens: 4, output_tokens: 3) }
  let(:adapter) { Ai::FakeAdapter.new }
  let(:gateway) { described_class.new(adapter: adapter) }

  it "returns a provider-neutral response" do
    adapter.enqueue_response(text: "Hello", request_id: "req_123", usage: usage)

    response = gateway.response(model: "gpt-4o", input: "Hi")

    expect(response).to have_attributes(text: "Hello", request_id: "req_123", usage: usage)
    expect(adapter.requests).to contain_exactly(model: "gpt-4o", input: "Hi")
  end

  it "streams deltas and returns the final provider-neutral response" do
    adapter.enqueue_stream(
      deltas: %w[Hel lo],
      text: "Hello",
      request_id: "req_123",
      usage: usage
    )
    deltas = []

    response = gateway.stream_response(model: "gpt-4o", input: "Hi") do |delta|
      deltas << delta
    end

    expect(deltas).to eq(%w[Hel lo])
    expect(response).to have_attributes(text: "Hello", request_id: "req_123", usage: usage)
  end

  it "rejects malformed adapter output" do
    adapter.enqueue_raw_response(Object.new)

    expect do
      gateway.response(model: "gpt-4o", input: "Hi")
    end.to raise_error(Ai::MalformedResponseError)
  end

  it "forwards a stable prompt cache key" do
    adapter.enqueue_response(text: "Hello", request_id: "req_123", usage: usage)

    gateway.response(model: "gpt-4o", input: "Hi", prompt_cache_key: "facet-pv-1")

    expect(adapter.requests.first).to include(prompt_cache_key: "facet-pv-1")
  end
end
