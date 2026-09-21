require "rails_helper"

RSpec.describe GenerationRuns::Stop do
  subject(:result) { described_class.call(generation_run: generation_run, now: now) }

  let(:now) { Time.zone.parse("2026-09-19 16:00:00") }
  let(:assistant_message) { create(:message, :assistant, status: :streaming, content: "") }
  let(:generation_run) do
    create(
      :generation_run,
      conversation_thread: assistant_message.conversation_thread,
      personality_version: assistant_message.personality_version,
      assistant_message: assistant_message,
      status: :running
    )
  end

  it "marks the run and its partial assistant message as stopped" do
    image = assistant_message.create_message_image!(
      source_avatar_object_key: "personalities/1/avatars/current.jpg"
    )

    expect(result).to be_success
    expect(generation_run.reload).to have_attributes(status: "stopped", completed_at: now)
    expect(assistant_message.reload).to be_stopped
    expect(image.reload).to have_attributes(status: "failed", error_code: "reply_stopped")
  end

  it "does not stop a terminal run" do
    generation_run.update!(status: :completed, completed_at: now)

    expect(result).not_to be_success
    expect(generation_run.reload).to be_completed
  end
end
