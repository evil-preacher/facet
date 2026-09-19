require "rails_helper"

RSpec.describe Ai::GenerateReplyJob do
  it "delegates a persisted run to the generation service" do
    generation_run = create(:generation_run)
    result = instance_double(Ai::GenerateReply::Result, error_code: nil)

    allow(Ai::GenerateReply).to receive(:call).and_return(result)

    described_class.perform_now(generation_run.id)

    expect(Ai::GenerateReply).to have_received(:call).with(generation_run: generation_run)
  end

  it "retries transient provider failures and returns the run to pending" do
    generation_run = create(:generation_run)
    assistant_message = create(
      :message,
      :assistant,
      conversation_thread: generation_run.conversation_thread,
      personality_version: generation_run.personality_version
    )
    generation_run.update!(assistant_message: assistant_message)
    result = instance_double(Ai::GenerateReply::Result, error_code: "timeout")
    allow(Ai::GenerateReply).to receive(:call) do
      generation_run.update!(status: :failed, error_code: "timeout", completed_at: Time.current)
      result
    end

    expect do
      described_class.perform_now(generation_run.id)
    end.to have_enqueued_job(described_class).once

    expect(generation_run.reload).to have_attributes(status: "pending", completed_at: nil)
    expect(generation_run.assistant_message.reload).to be_streaming
  end

  it "persists a terminal state before reraising an unexpected crash" do
    generation_run = create(:generation_run)
    allow(Ai::GenerateReply).to receive(:call).and_raise(ArgumentError, "private detail")

    expect do
      described_class.perform_now(generation_run.id)
    end.to raise_error(ArgumentError)

    expect(generation_run.reload).to have_attributes(
      status: "failed",
      error_code: "unexpected_error",
      error_message: "ArgumentError"
    )
  end

  it "does not retry terminal request errors" do
    generation_run = create(:generation_run)
    result = instance_double(Ai::GenerateReply::Result, error_code: "malformed_response")
    allow(Ai::GenerateReply).to receive(:call).and_return(result)

    expect do
      described_class.perform_now(generation_run.id)
    end.not_to have_enqueued_job(described_class)
  end

  it "marks the workflow failed when transient retries are exhausted" do
    generation_run = create(:generation_run)
    assistant_message = create(
      :message,
      :assistant,
      conversation_thread: generation_run.conversation_thread,
      personality_version: generation_run.personality_version
    )
    generation_run.update!(assistant_message: assistant_message)
    result = instance_double(Ai::GenerateReply::Result, error_code: "rate_limit")
    allow(Ai::GenerateReply).to receive(:call) do
      generation_run.update!(status: :failed, error_code: "rate_limit", completed_at: Time.current)
      result
    end
    job = described_class.new(generation_run.id)
    job.deserialize(
      job.serialize.merge(
        "executions" => described_class::MAX_ATTEMPTS - 1,
        "exception_executions" => {
          "[Ai::RetryableGenerationError]" => described_class::MAX_ATTEMPTS - 1
        }
      )
    )

    job.perform_now

    expect(generation_run.reload).to have_attributes(
      status: "failed",
      error_code: "rate_limit",
      error_message: "Model provider request failed after retries"
    )
    expect(assistant_message.reload).to be_failed
  end
end
