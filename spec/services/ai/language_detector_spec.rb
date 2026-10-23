require "rails_helper"

RSpec.describe Ai::LanguageDetector do
  it "detects Russian from the latest user message" do
    expect(described_class.call(I18n.t("app.flash.signed_in", locale: :ru))).to eq("ru")
  end

  it "detects English from the latest user message" do
    expect(described_class.call("Hello! How are you?")).to eq("en")
  end

  it "returns und when there is no meaningful alphabetic signal" do
    expect(described_class.call("123?!")).to eq("und")
  end
end
