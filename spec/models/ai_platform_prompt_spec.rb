require "rails_helper"

RSpec.describe AiPlatformPrompt, type: :model do
  it "computes a stable checksum from normalized content" do
    prompt = build(:ai_platform_prompt, content: "  Keep the character voice.  ")

    expect(prompt).to be_valid
    expect(prompt.content).to eq("Keep the character voice.")
    expect(prompt.checksum).to eq(Digest::SHA256.hexdigest(prompt.content))
  end

  it "allows only one active prompt for a provider and purpose" do
    create(:ai_platform_prompt)
    duplicate = build(:ai_platform_prompt, revision: 2)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:provider]).to be_present
  end

  it "finds only the active prompt for the requested provider" do
    create(:ai_platform_prompt, provider: "mistral", status: :retired)
    active = create(:ai_platform_prompt, provider: "openai")

    expect(described_class.active_for(provider: "OPENAI")).to eq(active)
    expect(described_class.active_for(provider: "mistral")).to be_nil
  end
end
