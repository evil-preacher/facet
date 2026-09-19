require "rails_helper"

RSpec.describe GenerationRuns::Retry do
  subject(:result) { described_class.call(generation_run: source_run) }

  let(:source_run) do
    create(
      :generation_run,
      status: :failed,
      error_code: "timeout",
      error_message: "Provider timeout",
      started_at: 1.minute.ago,
      completed_at: Time.current
    )
  end

  it "creates and enqueues a new run without overwriting the failed attempt" do
    source_run
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect do
      expect { result }.to have_enqueued_job(Ai::GenerateReplyJob).once
    end.to change(GenerationRun, :count).by(1)
      .and change(OutboxEvent, :count).by(1)
      .and change(Message, :count).by(1)

    expect(result).to be_success
    expect(source_run.reload).to be_failed
    expect(result.generation_run).to have_attributes(
      status: "pending",
      retry_of: source_run,
      user_message: source_run.user_message
    )
    expect(result.generation_run.assistant_message).to be_streaming
  end

  it "does not retry a run that is already active" do
    source_run.update!(status: :running)

    expect(result).not_to be_success
    expect(result.errors[:generation_run]).to be_present
    expect(source_run.reload).to be_running
  end

  it "does not retry inside an archived thread" do
    source_run.conversation_thread.update!(status: :archived)

    expect(result).not_to be_success
    expect(result.errors[:generation_run]).to be_present
    expect(source_run.reload).to be_failed
  end

  it "is idempotent when the same failed run is retried twice" do
    first = result

    expect do
      @second = described_class.call(generation_run: source_run)
    end.to change(GenerationRun, :count).by(0)
      .and change(Message, :count).by(0)

    expect(@second).to be_success
    expect(@second.generation_run).to eq(first.generation_run)
  end
end
