require "rails_helper"

RSpec.describe Ai::OpenAiAdapter do
  UsageDetails = Struct.new(:cached_tokens, keyword_init: true)
  ProviderUsage = Struct.new(
    :input_tokens,
    :input_tokens_details,
    :output_tokens,
    keyword_init: true
  )
  ProviderResponse = Struct.new(
    :id,
    :model,
    :output_text,
    :usage,
    :_request_id,
    keyword_init: true
  )
  ProviderEvent = Struct.new(:type, :delta, :response, keyword_init: true)

  class FakeResponsesResource
    attr_reader :parameters

    def initialize(response: nil, stream: nil)
      @response = response
      @stream = stream
    end

    def create(**parameters)
      @parameters = parameters
      @response
    end

    def stream(**parameters)
      @parameters = parameters
      @stream
    end
  end

  class FakeProviderStream
    include Enumerable

    attr_reader :_request_id

    def initialize(events, request_id:)
      @events = events
      @_request_id = request_id
    end

    def each(&block)
      @events.each(&block)
    end
  end

  def provider_response(request_id: "req_http")
    ProviderResponse.new(
      id: "resp_123",
      model: "gpt-4o-2024-11-20",
      _request_id: request_id,
      output_text: "Hello",
      usage: ProviderUsage.new(
        input_tokens: 12,
        input_tokens_details: UsageDetails.new(cached_tokens: 4),
        output_tokens: 3
      )
    )
  end

  it "maps an SDK response to the provider-neutral contract" do
    resource = FakeResponsesResource.new(response: provider_response)
    adapter = described_class.new(client: Struct.new(:responses).new(resource))

    response = adapter.response(model: "gpt-4o", input: "Hi")

    expect(resource.parameters).to eq(model: "gpt-4o", input: "Hi", store: false)
    expect(response).to have_attributes(
      text: "Hello",
      request_id: "req_http",
      model: "gpt-4o-2024-11-20",
      usage: Ai::Usage.new(input_tokens: 12, cached_input_tokens: 4, output_tokens: 3)
    )
  end

  it "maps SDK stream deltas and final usage" do
    completed = provider_response(request_id: nil)
    stream = FakeProviderStream.new(
      [
        ProviderEvent.new(type: :"response.output_text.delta", delta: "Hel"),
        ProviderEvent.new(type: :"response.output_text.delta", delta: "lo"),
        ProviderEvent.new(type: :"response.completed", response: completed)
      ],
      request_id: "req_stream"
    )
    resource = FakeResponsesResource.new(stream: stream)
    adapter = described_class.new(client: Struct.new(:responses).new(resource))
    deltas = []

    response = adapter.stream_response(model: "gpt-4o", input: "Hi") { |delta| deltas << delta }

    expect(deltas).to eq(%w[Hel lo])
    expect(response.request_id).to eq("req_stream")
    expect(response.model).to eq("gpt-4o-2024-11-20")
    expect(response.usage.cached_input_tokens).to eq(4)
  end

  it "normalizes an incomplete SDK payload" do
    resource = FakeResponsesResource.new(response: Object.new)
    adapter = described_class.new(client: Struct.new(:responses).new(resource))

    expect do
      adapter.response(model: "gpt-4o", input: "Hi")
    end.to raise_error(Ai::MalformedResponseError)
  end

  it "serializes provider-neutral input items and forwards the cache key" do
    resource = FakeResponsesResource.new(response: provider_response)
    adapter = described_class.new(client: Struct.new(:responses).new(resource))
    item = Ai::PromptBuilder::InputItem.new(role: "developer", content: "Stable prefix")

    adapter.response(model: "gpt-4o", input: [ item ], prompt_cache_key: "facet-pv-1")

    expect(resource.parameters).to eq(
      model: "gpt-4o",
      input: [ { role: "developer", content: "Stable prefix" } ],
      store: false,
      prompt_cache_key: "facet-pv-1"
    )
  end

  it "logs the exact request payload only when explicitly enabled in development" do
    resource = FakeResponsesResource.new(response: provider_response)
    adapter = described_class.new(client: Struct.new(:responses).new(resource))
    allow(Rails.env).to receive(:development?).and_return(true)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("AI_DEBUG_PAYLOADS").and_return("true")
    allow(Rails.logger).to receive(:info)

    adapter.response(model: "gpt-4o", input: "private prompt")

    expect(Rails.logger).to have_received(:info).with(
      include("OpenAI request payload", "private prompt", "model: \"gpt-4o\"")
    )
    expect(Rails.logger).to have_received(:info).with(
      include("OpenAI response", "req_http", "gpt-4o-2024-11-20")
    )
  end
end
