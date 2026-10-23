require "rails_helper"

RSpec.describe Ai::MistralAdapter do
  UsageDetails = Struct.new(:cached_tokens, keyword_init: true)
  ProviderUsage = Struct.new(
    :prompt_tokens,
    :prompt_tokens_details,
    :completion_tokens,
    keyword_init: true
  )
  ProviderMessage = Struct.new(:content, keyword_init: true)
  ProviderChoice = Struct.new(:message, keyword_init: true)
  ProviderResponse = Struct.new(
    :id,
    :model,
    :choices,
    :usage,
    :_request_id,
    keyword_init: true
  )
  ProviderEvent = Struct.new(:type, :delta, keyword_init: true)

  class FakeCompletionsResource
    attr_reader :parameters

    def initialize(response: nil, stream: nil)
      @response = response
      @stream = stream
    end

    def create(parameters)
      @parameters = parameters
      @response
    end

    def stream(parameters)
      @parameters = parameters
      @stream
    end
  end

  class FakeProviderStream
    include Enumerable

    attr_reader :_request_id

    def initialize(events, response:, request_id:)
      @events = events
      @response = response
      @_request_id = request_id
    end

    def each(&block)
      @events.each(&block)
    end

    def get_final_completion
      @response
    end
  end

  def provider_response(request_id: "req_http")
    ProviderResponse.new(
      id: "cmpl_123",
      model: "mistral-large-2512",
      _request_id: request_id,
      choices: [ ProviderChoice.new(message: ProviderMessage.new(content: "Hello")) ],
      usage: ProviderUsage.new(
        prompt_tokens: 12,
        prompt_tokens_details: UsageDetails.new(cached_tokens: 4),
        completion_tokens: 3
      )
    )
  end

  def client_for(resource)
    chat = Struct.new(:completions).new(resource)
    Struct.new(:chat).new(chat)
  end

  it "maps a Chat Completions response to the provider-neutral contract" do
    resource = FakeCompletionsResource.new(response: provider_response)
    adapter = described_class.new(client: client_for(resource))

    response = adapter.response(model: "mistral-large-2512", input: "Hi")

    expect(resource.parameters).to eq(
      model: "mistral-large-2512",
      messages: [ { role: "user", content: "Hi" } ]
    )
    expect(response).to have_attributes(
      text: "Hello",
      request_id: "req_http",
      model: "mistral-large-2512",
      usage: Ai::Usage.new(input_tokens: 12, cached_input_tokens: 4, output_tokens: 3)
    )
  end

  it "maps SDK stream deltas and final usage" do
    completed = provider_response(request_id: nil)
    stream = FakeProviderStream.new(
      [
        ProviderEvent.new(type: :"content.delta", delta: "Hel"),
        ProviderEvent.new(type: :"content.delta", delta: "lo")
      ],
      response: completed,
      request_id: "req_stream"
    )
    resource = FakeCompletionsResource.new(stream: stream)
    adapter = described_class.new(client: client_for(resource))
    deltas = []

    response = adapter.stream_response(model: "mistral-large-2512", input: "Hi") do |delta|
      deltas << delta
    end

    expect(deltas).to eq(%w[Hel lo])
    expect(response.request_id).to eq("req_stream")
    expect(response.model).to eq("mistral-large-2512")
    expect(response.usage.cached_input_tokens).to eq(4)
  end

  it "normalizes an incomplete SDK payload" do
    resource = FakeCompletionsResource.new(response: Object.new)
    adapter = described_class.new(client: client_for(resource))

    expect do
      adapter.response(model: "mistral-large-2512", input: "Hi")
    end.to raise_error(Ai::MalformedResponseError)
  end

  it "serializes input, maps developer messages to system, and forwards the cache key" do
    resource = FakeCompletionsResource.new(response: provider_response)
    adapter = described_class.new(client: client_for(resource))
    item = Ai::PromptBuilder::InputItem.new(role: "developer", content: "Stable prefix")

    adapter.response(
      model: "mistral-large-2512",
      input: [ item ],
      prompt_cache_key: "facet-pv-1"
    )

    expect(resource.parameters).to eq(
      model: "mistral-large-2512",
      messages: [ { role: "system", content: "Stable prefix" } ],
      prompt_cache_key: "facet-pv-1"
    )
  end

  it "forwards JSON Schema and deterministic sampling parameters" do
    resource = FakeCompletionsResource.new(response: provider_response)
    adapter = described_class.new(client: client_for(resource))
    schema = {
      name: "memory_candidates",
      schema: {
        type: "object",
        required: [ "candidates" ],
        properties: { candidates: { type: "array" } }
      }
    }

    adapter.response(
      model: "mistral-small-latest",
      input: "Return JSON",
      response_schema: schema,
      temperature: 0.1,
      max_output_tokens: 2_500
    )

    expect(resource.parameters).to include(
      temperature: 0.1,
      max_tokens: 2_500,
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "memory_candidates",
          strict: true,
          schema: schema.fetch(:schema)
        }
      }
    )
  end

  it "preserves multimodal text and image parts" do
    resource = FakeCompletionsResource.new(response: provider_response)
    adapter = described_class.new(client: client_for(resource))
    content = [
      { type: "text", text: "What is in the photo?" },
      {
        type: "image_url",
        image_url: { url: "data:image/jpeg;base64,cGhvdG8=" }
      }
    ]

    adapter.response(
      model: "mistral-large-2512",
      input: [ Ai::PromptBuilder::InputItem.new(role: "user", content: content) ]
    )

    expect(resource.parameters).to eq(
      model: "mistral-large-2512",
      messages: [ { role: "user", content: content } ]
    )
  end

  it "logs the exact request payload only when explicitly enabled in development" do
    resource = FakeCompletionsResource.new(response: provider_response)
    adapter = described_class.new(client: client_for(resource))
    allow(Rails.env).to receive(:development?).and_return(true)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("AI_DEBUG_PAYLOADS").and_return("true")
    allow(Rails.logger).to receive(:info)

    adapter.response(model: "mistral-large-2512", input: "private prompt")

    expect(Rails.logger).to have_received(:info).with(
      include("Mistral request payload", "private prompt", "model: \"mistral-large-2512\"")
    )
    expect(Rails.logger).to have_received(:info).with(
      include(
        "Mistral response",
        "req_http",
        "mistral-large-2512",
        "input_tokens=12",
        "cached_input_tokens=4",
        "cache_hit=true",
        "cached_percent=33.3"
      )
    )
  end

  it "redacts image data from debug payload logs" do
    resource = FakeCompletionsResource.new(response: provider_response)
    adapter = described_class.new(client: client_for(resource))
    allow(Rails.env).to receive(:development?).and_return(true)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("AI_DEBUG_PAYLOADS").and_return("true")
    logged = []
    allow(Rails.logger).to receive(:info) { |message| logged << message }
    secret_data = "data:image/jpeg;base64,private-image"

    adapter.response(
      model: "mistral-large-2512",
      input: [
        Ai::PromptBuilder::InputItem.new(
          role: "user",
          content: [
            { type: "text", text: "Look" },
            { type: "image_url", image_url: { url: secret_data } }
          ]
        )
      ]
    )

    output = logged.join("\n")
    expect(output).to include("[image data redacted]")
    expect(output).not_to include(secret_data)
  end
end
