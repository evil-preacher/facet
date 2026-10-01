require "rails_helper"

RSpec.describe Ai::OpenaiAdapter do
  OpenaiUsageDetails = Struct.new(:cached_tokens, keyword_init: true)
  OpenaiProviderUsage = Struct.new(:prompt_tokens, :prompt_tokens_details, :completion_tokens, keyword_init: true)
  OpenaiProviderMessage = Struct.new(:content, keyword_init: true)
  OpenaiProviderChoice = Struct.new(:message, keyword_init: true)
  OpenaiProviderResponse = Struct.new(:id, :model, :choices, :usage, :_request_id, keyword_init: true)

  it "preserves developer roles and normalizes OpenAI usage" do
    completion = OpenaiProviderResponse.new(
      id: "chatcmpl_123", model: "gpt-4o-2024-11-20", _request_id: "req_123",
      choices: [ OpenaiProviderChoice.new(message: OpenaiProviderMessage.new(content: "Hello")) ],
      usage: OpenaiProviderUsage.new(
        prompt_tokens: 10, prompt_tokens_details: OpenaiUsageDetails.new(cached_tokens: 2), completion_tokens: 3
      )
    )
    resource = double("completions")
    client = double("client", chat: double("chat", completions: resource))
    allow(resource).to receive(:create).and_return(completion)

    response = described_class.new(client: client).response(
      model: "gpt-4o-2024-11-20",
      input: [ { role: "developer", content: "Rules" }, { role: "user", content: "Hi" } ],
      prompt_cache_key: "thread-1"
    )

    expect(resource).to have_received(:create).with(
      model: "gpt-4o-2024-11-20",
      messages: [ { role: "developer", content: "Rules" }, { role: "user", content: "Hi" } ],
      prompt_cache_key: "thread-1"
    )
    expect(response).to have_attributes(
      text: "Hello", request_id: "req_123", model: "gpt-4o-2024-11-20",
      usage: Ai::Usage.new(input_tokens: 10, cached_input_tokens: 2, output_tokens: 3)
    )
  end

  it "requests token usage for streamed responses" do
    completion = OpenaiProviderResponse.new(
      id: "chatcmpl_123", model: "gpt-4o-2024-11-20", _request_id: "req_123",
      choices: [ OpenaiProviderChoice.new(message: OpenaiProviderMessage.new(content: "OK")) ],
      usage: OpenaiProviderUsage.new(prompt_tokens: 10, completion_tokens: 1)
    )
    stream = double("stream", _request_id: "req_123", get_final_completion: completion)
    allow(stream).to receive(:each).and_yield(double("event", type: "content.delta", delta: "OK"))
    resource = double("completions")
    allow(resource).to receive(:stream).and_return(stream)
    client = double("client", chat: double("chat", completions: resource))
    deltas = []

    response = described_class.new(client: client).stream_response(
      model: "gpt-4o-2024-11-20", input: "Hi"
    ) { |delta| deltas << delta }

    expect(resource).to have_received(:stream).with(
      model: "gpt-4o-2024-11-20", messages: [ { role: "user", content: "Hi" } ],
      stream_options: { include_usage: true }
    )
    expect(deltas).to eq([ "OK" ])
    expect(response.usage).to eq(Ai::Usage.new(input_tokens: 10, cached_input_tokens: 0, output_tokens: 1))
  end
end
