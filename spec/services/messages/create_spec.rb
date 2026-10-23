require "rails_helper"

RSpec.describe Messages::Create do
  CreateUpload = Struct.new(:data, :original_filename) do
    def read(length)
      data.byteslice(0, length)
    end

    def rewind; end
  end

  let(:user) { create(:user, :confirmed) }
  let(:personality) do
    Personalities::Create.call(
      user: user,
      attributes: {
        name: "Alice",
        base_character: "Curious.",
        communication_style: "Speaks naturally."
      }
    ).personality
  end
  let(:thread_result) do
    ConversationThreads::Create.call(
      personality: personality,
      user: user,
      attributes: {
        content: "First message",
        client_token: "11111111-1111-4111-8111-111111111111"
      }
    )
  end
  let(:conversation_thread) { thread_result.conversation_thread }

  def create_message(content:, token:, current_user: user, extra: {}, storage: ObjectStorage::S3Store.default)
    described_class.call(
      conversation_thread: conversation_thread,
      user: current_user,
      attributes: {
        content: content,
        client_token: token,
        user_id: create(:user).id
      }.merge(extra),
      storage: storage
    )
  end

  it "appends messages in a stable order using the current personality version" do
    second = create_message(
      content: "Second message",
      token: "22222222-2222-4222-8222-222222222222"
    )
    third = create_message(
      content: "Third message",
      token: "33333333-3333-4333-8333-333333333333"
    )

    expect(second).to be_success
    expect(third).to be_success
    expect(conversation_thread.messages.user.order(:position).pluck(:position, :content)).to eq(
      [
        [ 1, "First message" ],
        [ 3, "Second message" ],
        [ 5, "Third message" ]
      ]
    )
    expect(third.message.personality_version).to eq(personality.current_version)
    expect(second.message.language).to eq("en")
  end

  it "atomically prepares and enqueues one assistant generation" do
    conversation_thread
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect do
      @result = create_message(
        content: "Reply to me",
        token: "22222222-2222-4222-8222-222222222222"
      )
    end.to have_enqueued_job(Ai::GenerateReplyJob).once
      .and change(GenerationRun, :count).by(1)
      .and change(OutboxEvent, :count).by(1)
      .and change(Message, :count).by(2)

    expect(@result.assistant_message).to have_attributes(
      role: "assistant",
      status: "streaming",
      content: ""
    )
    expect(@result.generation_run).to have_attributes(
      user_message: @result.message,
      assistant_message: @result.assistant_message,
      status: "pending"
    )
  end

  it "is idempotent for a repeated client token" do
    conversation_thread
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    token = "22222222-2222-4222-8222-222222222222"
    first_result = create_message(content: "Once", token: token)

    expect do
      expect do
        @repeated_result = create_message(content: "Duplicate", token: token)
      end.not_to have_enqueued_job(Ai::GenerateReplyJob)
    end.not_to change(Message, :count)

    expect(first_result).to be_created
    expect(@repeated_result).to be_success
    expect(@repeated_result).not_to be_created
    expect(@repeated_result.message).to eq(first_result.message)
    expect(@repeated_result.generation_run).to eq(first_result.generation_run)
    expect(@repeated_result.message.content).to eq("Once")
  end

  it "prepares a referenced photo for an explicit request when the avatar is ready" do
    conversation_thread
    personality.update!(
      avatar_status: :ready,
      avatar_object_key: "personalities/#{personality.id}/avatars/current.jpg",
      avatar_content_type: "image/jpeg",
      avatar_byte_size: 123,
      avatar_generated_at: Time.current,
      avatar_source_version: personality.current_version
    )

    result = create_message(
      content: "Send me a photo of how you look now",
      token: "22222222-2222-4222-8222-222222222222"
    )

    expect(result).to be_success
    expect(result.assistant_message.message_image).to have_attributes(
      status: "pending",
      source_avatar_object_key: personality.avatar_object_key
    )
  end

  it "does not prepare a photo when the avatar is unavailable" do
    conversation_thread

    result = create_message(
      content: "Send me a photo of how you look now",
      token: "22222222-2222-4222-8222-222222222222"
    )

    expect(result).to be_success
    expect(result.assistant_message.message_image).to be_nil
  end

  it "uploads and attaches an image without requiring a text caption" do
    bytes = "\xFF\xD8\xFFphoto".b
    upload = CreateUpload.new(bytes, "portrait.jpg")
    storage = instance_double(ObjectStorage::S3Store, upload: nil, delete: nil)

    result = create_message(
      content: "",
      token: "22222222-2222-4222-8222-222222222222",
      extra: { image: upload },
      storage: storage
    )

    expect(result).to be_success
    expect(storage).to have_received(:upload).with(
      key: match(%r{\Amessages/attachments/.+\.jpg\z}),
      body: bytes,
      content_type: "image/jpeg"
    )
    expect(result.message).to have_attributes(content: "", language: "und")
    expect(result.message.attachment).to have_attributes(
      content_type: "image/jpeg",
      byte_size: bytes.bytesize,
      original_filename: "portrait.jpg"
    )
  end

  it "rejects a file whose bytes are not a supported image" do
    result = create_message(
      content: "",
      token: "22222222-2222-4222-8222-222222222222",
      extra: { image: CreateUpload.new("not-image", "fake.jpg") }
    )

    expect(result).not_to be_success
    expect(result.errors[:image]).to be_present
  end

  it "rejects blank content" do
    result = create_message(
      content: "   ",
      token: "22222222-2222-4222-8222-222222222222"
    )

    expect(result).not_to be_success
    expect(result.errors[:content]).to be_present
  end

  it "rejects an invalid client token" do
    result = create_message(content: "Hello", token: "not-a-uuid")

    expect(result).not_to be_success
    expect(result.errors[:client_token]).to be_present
  end

  it "rejects a user who does not own the thread" do
    result = create_message(
      content: "Another person's message",
      token: "22222222-2222-4222-8222-222222222222",
      current_user: create(:user, :confirmed)
    )

    expect(result).not_to be_success
    expect(result.errors[:user]).to be_present
  end

  it "does not append messages to an archived thread" do
    conversation_thread.update!(status: :archived)

    result = create_message(
      content: "Later message",
      token: "22222222-2222-4222-8222-222222222222"
    )

    expect(result).not_to be_success
    expect(result.errors[:conversation_thread]).to be_present
  end

  it "does not append messages when the personality is archived" do
    conversation_thread
    personality.update!(status: :archived)

    result = create_message(
      content: "Later message",
      token: "22222222-2222-4222-8222-222222222222"
    )

    expect(result).not_to be_success
    expect(result.errors[:conversation_thread]).to be_present
  end
end
