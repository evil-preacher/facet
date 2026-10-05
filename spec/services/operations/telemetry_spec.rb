require "rails_helper"

RSpec.describe Operations::Telemetry do
  it "emits structured allowlisted fields without private content" do
    logger = instance_double(ActiveSupport::Logger)
    allow(Rails).to receive(:logger).and_return(logger)
    expect(logger).to receive(:info) do |line|
      payload = JSON.parse(line)
      expect(payload).to include("event" => "model_call", "status" => "completed")
      expect(payload).not_to have_key("content")
      expect(line).not_to include("secret conversation")
    end

    described_class.emit("model_call", status: "completed", content: "secret conversation")
  end
end
