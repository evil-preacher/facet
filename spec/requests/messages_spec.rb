require "rails_helper"

RSpec.describe "Messages", type: :request do
  let(:user) { create(:user, :confirmed) }
  let!(:profile) { create(:profile, user: user) }
  let(:personality) { create(:personality, :active, user: user) }
  let(:conversation_thread) do
    ConversationThreads::Create.call(
      personality: personality,
      user: user,
      attributes: { content: "First message", client_token: SecureRandom.uuid }
    ).conversation_thread
  end

  def sign_in(user_to_sign_in = user)
    challenge, code = LoginChallenge.issue_for!(user: user_to_sign_in, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  it "appends a message with a Turbo Stream response" do
    sign_in

    expect do
      post personality_conversation_thread_messages_path(personality, conversation_thread),
           params: {
             message: {
               content: "New message",
               client_token: "22222222-2222-4222-8222-222222222222"
             }
           },
           as: :turbo_stream
    end.to change(conversation_thread.messages, :count).by(2)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(turbo-stream action="append" target="messages"))
    expect(response.body).to include("New message")
    expect(response.body).to include("generation_stream")
    expect(response.body).to include("#{personality.name} is composing a reply")
    expect(response.body).to match(
      /data-message-author>\s*#{Regexp.escape(personality.name)}\s*</
    )
  end

  it "accepts an image attachment and renders it in the Turbo response" do
    sign_in
    bytes = "\xFF\xD8\xFFphoto".b
    upload = Rack::Test::UploadedFile.new(
      StringIO.new(bytes),
      "image/jpeg",
      original_filename: "portrait.jpg"
    )
    storage = instance_double(
      ObjectStorage::S3Store,
      upload: nil,
      delete: nil,
      presigned_url: "http://minio.local/facet/user-photo.jpg"
    )
    allow(ObjectStorage::S3Store).to receive(:default).and_return(storage)

    post personality_conversation_thread_messages_path(personality, conversation_thread),
         params: {
           message: {
             content: "",
             image: upload,
             client_token: "22222222-2222-4222-8222-222222222222"
           }
         },
         headers: { "ACCEPT" => Mime[:turbo_stream].to_s }

    message = conversation_thread.messages.user.order(:position).last
    expect(response).to have_http_status(:ok)
    expect(message.content).to eq("")
    expect(message.attachment).to have_attributes(
      content_type: "image/jpeg",
      byte_size: bytes.bytesize
    )
    expect(response.body).to include("http://minio.local/facet/user-photo.jpg")
  end

  it "does not duplicate a repeated submission" do
    sign_in
    params = {
      message: {
        content: "Only once",
        client_token: "22222222-2222-4222-8222-222222222222"
      }
    }

    post personality_conversation_thread_messages_path(personality, conversation_thread),
         params: params

    expect do
      post personality_conversation_thread_messages_path(personality, conversation_thread),
           params: params
    end.not_to change(Message, :count)

    expect(response).to redirect_to(
      personality_conversation_thread_path(personality, conversation_thread)
    )
  end

  it "returns composer errors for a blank Turbo Stream submission" do
    sign_in

    post personality_conversation_thread_messages_path(personality, conversation_thread),
         params: {
           message: { content: " ", client_token: SecureRandom.uuid }
         },
         as: :turbo_stream

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(%(turbo-stream action="replace" target="message_composer"))
    expect(response.body).to include("can&#39;t be blank")
  end

  it "does not allow posting to another user's thread" do
    other_user = create(:user, :confirmed)
    create(:profile, user: other_user)
    other_personality = create(:personality, :active, user: other_user)
    other_thread = ConversationThreads::Create.call(
      personality: other_personality,
      user: other_user,
      attributes: { content: "Another person's thread", client_token: SecureRandom.uuid }
    ).conversation_thread
    sign_in

    expect do
      post personality_conversation_thread_messages_path(other_personality, other_thread),
           params: {
             message: { content: "Intrusion", client_token: SecureRandom.uuid }
           }
    end.not_to change(Message, :count)

    expect(response).to have_http_status(:not_found)
  end
end
