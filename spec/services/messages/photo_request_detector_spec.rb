require "rails_helper"

RSpec.describe Messages::PhotoRequestDetector do
  it "recognizes explicit Russian and English photo requests" do
    expect(described_class.call("Send me a photo of how you are sitting now")).to be(true)
    expect(described_class.call("Take a selfie now")).to be(true)
    expect(described_class.call("Can you send me a picture?")).to be(true)
  end

  it "does not trigger on incidental discussion of photos" do
    expect(described_class.call("I sorted old photos yesterday")).to be(false)
    expect(described_class.call("Tell me what you think about this")).to be(false)
    expect(described_class.call("photo")).to be(false)
  end
end
