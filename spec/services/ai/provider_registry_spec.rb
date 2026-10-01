require "rails_helper"

RSpec.describe Ai::ProviderRegistry do
  it "builds a Mistral gateway" do
    expect(described_class.gateway_for("mistral")).to be_a(Ai::Gateway)
  end

  it "builds an OpenAI gateway" do
    expect(described_class.gateway_for("openai")).to be_a(Ai::Gateway)
  end

  it "rejects a provider without a configured adapter" do
    expect { described_class.gateway_for("unknown") }
      .to raise_error(Ai::ValidationError, /not configured/)
  end
end
