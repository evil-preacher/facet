require "rails_helper"

RSpec.describe Ai::PromptCatalog do
  it "reads only the active database revision" do
    described_class.publish(key: "thread_summary", content: "Revised summary instructions")

    expect(described_class.content("thread_summary")).to eq("Revised summary instructions")
    expect(AiPromptRevision.where(key: "thread_summary", status: "retired").count).to eq(1)
  end

  it "fails clearly when a template has no active database revision" do
    AiPromptRevision.where(key: "thread_summary").delete_all

    expect { described_class.content("thread_summary") }
      .to raise_error(Ai::PromptCatalog::MissingPromptError, /thread_summary/)
  end
end
