require "rails_helper"

RSpec.describe Relationships::Update::Schema do
  it "rejects a claimed change without evidence from the current turn" do
    expect do
      described_class.parse(
        text: '{"status":"changed","summary":"They agreed to speak informally.","source_message_ids":[]}',
        previous_summary: "", allowed_message_ids: [ 1, 2 ]
      )
    end.to raise_error(described_class::InvalidOutput)
  end

  it "rejects changes disguised as unchanged" do
    expect do
      described_class.parse(
        text: '{"status":"unchanged","summary":"New interpretation.","source_message_ids":[]}',
        previous_summary: "Old summary.", allowed_message_ids: [ 1, 2 ]
      )
    end.to raise_error(described_class::InvalidOutput)
  end

  it "treats a scene-only response as no durable relationship change" do
    user_message = instance_double(Message, id: 12, content: "Yes\n*I wave from the doorway*")
    parsed = described_class.parse_update(
      text: { status: "changed", summary: "The character waves back and says goodbye.",
              source_message_ids: [ 12, 13 ], durable_evidence_quote: "I wave from the doorway" }.to_json,
      previous_summary: "They speak openly.", user_message: user_message,
      allowed_message_ids: [ 12, 13 ]
    )

    expect(parsed).to eq(status: "unchanged", summary: "They speak openly.", source_message_ids: [])
  end
end
