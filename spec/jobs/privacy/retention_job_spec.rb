require "rails_helper"

RSpec.describe Privacy::RetentionJob do
  it "removes old diagnostics while keeping recent records" do
    old_run = create(:generation_run, prompt_manifest: { "memory_ids" => [ 1 ] },
                                     error_message: "private detail")
    recent_run = create(:generation_run, prompt_manifest: { "memory_ids" => [ 2 ] })
    event = OutboxEvent.create!(event_key: "old-error", job_class: "Ai::GenerateReplyJob",
                                queue_name: "conversation", arguments: [ old_run.id ],
                                available_at: Time.current, last_error: "private error")
    old_run.update_columns(created_at: 31.days.ago)
    event.update_columns(created_at: 31.days.ago)

    described_class.perform_now

    expect(old_run.reload.prompt_manifest).to eq({})
    expect(old_run.error_message).to be_nil
    expect(recent_run.reload.prompt_manifest).to eq({ "memory_ids" => [ 2 ] })
    expect(event.reload.last_error).to be_nil
  end
end
