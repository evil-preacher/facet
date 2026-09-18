require "rails_helper"

RSpec.describe GenerationRuns::Retry do
  subject(:result) { described_class.call(generation_run: generation_run) }

  let(:generation_run) do
    create(
      :generation_run,
      status: :failed,
      error_code: "timeout",
      error_message: "Provider timeout",
      started_at: 1.minute.ago,
      completed_at: Time.current
    )
  end

  it "returns a failed run to a clean pending state" do
    expect(result).to be_success
    expect(generation_run.reload).to have_attributes(
      status: "pending",
      error_code: nil,
      error_message: nil,
      started_at: nil,
      completed_at: nil
    )
  end

  it "does not retry a run that is already active" do
    generation_run.update!(status: :running)

    expect(result).not_to be_success
    expect(result.errors[:generation_run]).to be_present
    expect(generation_run.reload).to be_running
  end

  it "does not retry inside an archived thread" do
    generation_run.conversation_thread.update!(status: :archived)

    expect(result).not_to be_success
    expect(result.errors[:generation_run]).to be_present
    expect(generation_run.reload).to be_failed
  end
end
