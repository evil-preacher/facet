require "rails_helper"

RSpec.describe Ai::TokenCounter do
  subject(:counter) { described_class.new }

  it "provides a deterministic conservative estimate" do
    expect(counter.count("Hello 🌍🌎🌏")).to eq(9)
  end

  it "truncates from either side within the requested budget" do
    expect(counter.truncate("abcdef", 3)).to eq("abc")
    expect(counter.truncate("abcdef", 3, from: :end)).to eq("def")
  end
end
