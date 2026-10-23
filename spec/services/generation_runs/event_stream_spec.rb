require "rails_helper"

RSpec.describe GenerationRuns::EventStream do
  let(:assistant_message) do
    create(:message, :assistant, status: :completed, content: "Hello!")
  end
  let(:generation_run) do
    create(
      :generation_run,
      conversation_thread: assistant_message.conversation_thread,
      personality_version: assistant_message.personality_version,
      assistant_message: assistant_message,
      status: :completed,
      completed_at: Time.current
    )
  end

  it "emits only text after the reconnect cursor, usage, and done" do
    create(
      :model_call,
      generation_run: generation_run,
      personality: generation_run.conversation_thread.personality,
      user: generation_run.conversation_thread.personality.user,
      status: :completed,
      input_tokens: 12,
      cached_input_tokens: 4,
      output_tokens: 3,
      cost_microusd: 10,
      pricing_version: "2026-09",
      response_model: "gpt-4o-2024-11-20",
      completed_at: Time.current
    )

    events = described_class.new(generation_run: generation_run, cursor: 3).each.to_a.join

    expect(events).to include("event: delta", "\"delta\":\"lo!\"")
    expect(events).to include("event: usage", "\"input_tokens\":12")
    expect(events).to include("\"model\":\"gpt-4o-2024-11-20\"")
    expect(events).to include("event: done", "\"status\":\"completed\"")
    expect(events).not_to include("\"delta\":\"Hello!\"")
  end

  it "includes sanitized rendered Markdown in the completed event" do
    assistant_message.update!(content: "**Hello!** <script>alert(1)</script>")

    events = described_class.new(generation_run: generation_run).each.to_a.join
    done_data = events.lines.find { |line| line.start_with?("data: {\"status\":\"completed\"") }

    expect(events).to include("event: done", "<strong>Hello!</strong>")
    expect(done_data).not_to include("<script>")
  end

  it "emits a safe error for a failed run" do
    generation_run.update!(status: :failed, error_code: "timeout", error_message: "Safe timeout")
    assistant_message.update!(status: :failed)

    events = described_class.new(generation_run: generation_run).each.to_a.join

    expect(events).to include("event: error", "\"code\":\"timeout\"", "Safe timeout")
  end

  it "emits a signed image URL before done when the requested photo is ready" do
    create(
      :message_image,
      message: assistant_message,
      status: :ready,
      object_key: "messages/#{assistant_message.id}/images/1.jpg",
      content_type: "image/jpeg",
      byte_size: 100,
      generated_at: Time.current
    )
    storage = instance_double(
      ObjectStorage::S3Store,
      presigned_url: "http://minio.local/facet/photo.jpg"
    )
    allow(ObjectStorage::S3Store).to receive(:default).and_return(storage)

    events = described_class.new(generation_run: generation_run).each.to_a.join

    expect(events).to include(
      "event: image",
      "\"url\":\"http://minio.local/facet/photo.jpg\"",
      "event: done"
    )
    expect(events.index("event: image")).to be < events.index("event: done")
  end

  it "removes the placeholder when the character declines the photo" do
    create(:message_image, message: assistant_message, status: :declined)

    events = described_class.new(generation_run: generation_run).each.to_a.join

    expect(events).to include(
      "event: image_declined",
      "event: done"
    )
  end

  it "keeps the stream open while the requested photo is pending" do
    create(:message_image, message: assistant_message, status: :pending)
    times = [ 0.0, 30.0 ]

    events = described_class.new(
      generation_run: generation_run,
      max_duration: 25,
      sleeper: ->(_seconds) { },
      clock: -> { times.shift || 30.0 }
    ).each.to_a.join

    expect(events).to include("event: delta")
    expect(events).not_to include("event: done")
  end

  it "treats an invalid reconnect cursor as the beginning" do
    events = described_class.new(generation_run: generation_run, cursor: "invalid").each.to_a.join

    expect(events).to include("\"delta\":\"Hello!\"")
  end

  it "stops polling when the client closes the stream" do
    pending_run = create(:generation_run)
    sleeper = double("sleeper")
    allow(sleeper).to receive(:call)
    stream = described_class.new(generation_run: pending_run,
                                 sleeper: ->(seconds) { sleeper.call(seconds) })

    stream.each { break }

    expect(sleeper).not_to have_received(:call)
  end
end
