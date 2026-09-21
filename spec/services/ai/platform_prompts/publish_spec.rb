require "rails_helper"

RSpec.describe Ai::PlatformPrompts::Publish do
  it "publishes immutable revisions and retires the previous prompt" do
    first = described_class.call(provider: "mistral", content: "First correction")
    second = described_class.call(provider: "mistral", content: "Second correction")

    expect(first.reload).to be_status_retired
    expect(second).to have_attributes(
      provider: "mistral",
      purpose: "conversation",
      revision: 2,
      content: "Second correction",
      status: "active"
    )
    expect(AiPlatformPrompt.active_for(provider: "mistral")).to eq(second)
  end

  it "does not create a revision when the active content is unchanged" do
    first = described_class.call(provider: "mistral", content: "Same correction")

    expect do
      expect(described_class.call(provider: "MISTRAL", content: " Same correction ")).to eq(first)
    end.not_to change(AiPlatformPrompt, :count)
  end
end
