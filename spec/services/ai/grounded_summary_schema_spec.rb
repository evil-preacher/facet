require "rails_helper"

RSpec.describe Ai::GroundedSummarySchema do
  it "uses the compact JSON Schema subset accepted by Mistral" do
    serialized = described_class::RESPONSE_SCHEMA.to_json

    expect(serialized).not_to match(/minLength|maxLength|minItems|maxItems|uniqueItems|minimum|maximum|format/)
  end

  it "accepts a grounded structured summary" do
    parsed = described_class.parse(
      text: '{"summary":"They agreed to meet Friday.","source_message_ids":[4,5]}',
      allowed_message_ids: [ 4, 5 ]
    )
    expect(parsed).to eq(summary: "They agreed to meet Friday.", source_message_ids: [ 4, 5 ])
  end

  it "rejects unknown provenance" do
    expect do
      described_class.parse(
        text: '{"summary":"An unsupported claim.","source_message_ids":[99]}',
        allowed_message_ids: [ 4, 5 ]
      )
    end.to raise_error(described_class::InvalidOutput)
  end
end
