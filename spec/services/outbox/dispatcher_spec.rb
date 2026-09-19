require "rails_helper"

RSpec.describe Outbox::Dispatcher do
  let(:generation_run) { create(:generation_run) }
  let!(:event) do
    Outbox::Publish.call(
      event_key: "generate-reply:#{generation_run.id}",
      job_class: Ai::GenerateReplyJob,
      arguments: [ generation_run.id ]
    )
  end

  it "enqueues ready work once and marks it dispatched" do
    expect { described_class.call }.to have_enqueued_job(Ai::GenerateReplyJob)
      .with(generation_run.id).on_queue("conversation").once

    expect(event.reload).to have_attributes(status: "dispatched", attempts_count: 1)
  end

  it "keeps work discoverable when Redis enqueue fails" do
    allow(Ai::GenerateReplyJob).to receive(:set).and_raise(RedisClient::CannotConnectError)

    expect { described_class.call }.not_to raise_error

    expect(event.reload).to have_attributes(status: "pending", attempts_count: 1)
    expect(event.last_error).to include("RedisClient::CannotConnectError")
    expect(event.available_at).to be > event.created_at
  end

  it "does not dispatch the same event twice" do
    described_class.call
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { described_class.call }.not_to have_enqueued_job(Ai::GenerateReplyJob)
  end
end
