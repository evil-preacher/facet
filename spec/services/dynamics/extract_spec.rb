require "rails_helper"

RSpec.describe Dynamics::Extract do
  let(:message) { Struct.new(:id, :content).new(17, nil) }

  it "records direct jealousy and attraction statements without guessing intent" do
    {
      "I feel jealous." => "jealousy",
      "I feel jealous when you mention them." => "jealousy",
      "I feel attracted to you." => "attraction",
      "I don't feel attracted to you anymore." => "boundary",
      "I am not jealous anymore." => "boundary",
      "Please don't contact me for a while." => "space_request"
    }.each do |content, expected|
      message.content = content
      expect(described_class.call(message: message)).to include(
        "kind" => expected, "source_message_ids" => [ 17 ]
      )
    end
  end

  it "rejects roleplay, questions, quotations, hypotheticals and third-party stories" do
    [
      "*I feel jealous*", "What if I felt jealous?", "I feel jealous?",
      "She said: I feel attracted to you.", "\"I feel attracted to you\"",
      "Imagine I feel attracted to you"
    ].each do |content|
      message.content = content
      expect(described_class.call(message: message).fetch("kind")).to eq("none")
    end
  end
end
