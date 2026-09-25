require "rails_helper"

RSpec.describe "Relationship context jobs" do
  let(:generation_run) { create(:generation_run) }

  it "retries an update rejected by the scope check" do
    result = Relationships::Update::Result.new(version: nil, error_code: "scope_violation")
    allow(Relationships::Update).to receive(:call).and_return(result)

    expect do
      Ai::RelationshipUpdateJob.perform_now(generation_run.id)
    end.to have_enqueued_job(Ai::RelationshipUpdateJob).once
  end

  it "retries an invalid consolidation result" do
    result = Relationships::Consolidate::Result.new(version: nil, error_code: "invalid_output")
    allow(Relationships::Consolidate).to receive(:call).and_return(result)

    expect do
      Ai::RelationshipConsolidationJob.perform_now(generation_run.id)
    end.to have_enqueued_job(Ai::RelationshipConsolidationJob).once
  end
end
