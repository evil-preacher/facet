require "rails_helper"

RSpec.describe Ai::BflImageAdapter do
  let(:client) { instance_double(Ai::BflImageAdapter::HttpClient) }
  let(:adapter) do
    described_class.new(
      client: client,
      sleeper: ->(_seconds) { },
      clock: ->(_clock_id) { 0.0 }
    )
  end
  let(:jpeg) { "\xFF\xD8\xFFimage".b }

  it "submits the configured portrait request, polls, and downloads the result" do
    allow(client).to receive(:post_json).and_return(
      response(body: { "id" => "request-1", "polling_url" => "https://api.bfl.ai/v1/get_result?id=1" }.to_json)
    )
    allow(client).to receive(:get_json).and_return(
      response(body: { "status" => "Ready", "result" => { "sample" => "https://delivery.bfl.ai/image.jpg" } }.to_json)
    )
    allow(client).to receive(:download).and_return(response(body: jpeg))

    result = adapter.generate(model: "flux-2-klein-9b", prompt: "portrait")

    expect(client).to have_received(:post_json).with(
      "/flux-2-klein-9b",
      {
        prompt: "portrait",
        width: 768,
        height: 1024,
        safety_tolerance: 5,
        output_format: "jpeg"
      }
    )
    expect(client).to have_received(:get_json).with("https://api.bfl.ai/v1/get_result?id=1")
    expect(client).to have_received(:download).with("https://delivery.bfl.ai/image.jpg")
    expect(result).to have_attributes(
      bytes: jpeg,
      content_type: "image/jpeg",
      request_id: "request-1",
      model: "flux-2-klein-9b"
    )
  end

  it "passes reference images as base64 without exposing them in debug metadata" do
    allow(client).to receive(:post_json).and_return(
      response(body: { "id" => "request-2", "polling_url" => "https://api.bfl.ai/poll/2" }.to_json)
    )
    allow(client).to receive(:get_json).and_return(
      response(body: { "status" => "Ready", "result" => { "sample" => "https://delivery.bfl.ai/2.jpg" } }.to_json)
    )
    allow(client).to receive(:download).and_return(response(body: jpeg))

    adapter.generate(model: "flux-2-klein-9b", prompt: "new scene", reference_images: [ "face".b ])

    expect(client).to have_received(:post_json) do |_path, payload|
      expect(payload[:input_image]).to eq(Base64.strict_encode64("face"))
    end
  end

  it "maps provider failure statuses to retryable errors" do
    allow(client).to receive(:post_json).and_return(
      response(body: { "id" => "request-3", "polling_url" => "https://api.bfl.ai/poll/3" }.to_json)
    )
    allow(client).to receive(:get_json).and_return(
      response(body: { "status" => "Failed" }.to_json)
    )

    expect do
      adapter.generate(model: "flux-2-klein-9b", prompt: "portrait")
    end.to raise_error(Ai::ProviderError)
  end

  it "maps rate limiting to a retryable error" do
    allow(client).to receive(:post_json).and_return(response(status: 429, body: "{}"))

    expect do
      adapter.generate(model: "flux-2-klein-9b", prompt: "portrait")
    end.to raise_error(Ai::RateLimitError)
  end

  def response(status: 200, body:, headers: {})
    Ai::BflImageAdapter::HttpResponse.new(status: status, headers: headers, body: body)
  end
end
