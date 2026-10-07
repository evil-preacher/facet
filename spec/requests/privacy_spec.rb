require "rails_helper"

RSpec.describe "Privacy", type: :request do
  let(:user) { create(:user, :confirmed) }
  let!(:profile) { create(:profile, user: user) }

  def sign_in(owner = user)
    challenge, code = LoginChallenge.issue_for!(user: owner, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  it "exports only the signed-in user's data as an attachment" do
    mine = create(:personality, :active, user: user, name: "Mine")
    other = create(:personality, :active, name: "Secret")
    create(:message, conversation_thread: create(:conversation_thread, personality: mine), content: "My text")
    create(:message, conversation_thread: create(:conversation_thread, personality: other), content: "Their text")
    sign_in

    get data_export_path

    expect(response).to have_http_status(:ok)
    expect(response.headers.fetch("Content-Disposition")).to include("attachment")
    expect(response.headers.fetch("Cache-Control")).to include("no-store")
    data = response.parsed_body
    expect(data.fetch("account").fetch("email")).to eq(user.email)
    expect(response.body).to include("My text")
    expect(response.body).not_to include("Their text", "Secret")
  end

  it "denies another user's deletion request" do
    other = create(:personality, :active)
    sign_in

    delete personality_path(other)

    expect(response).to have_http_status(:not_found)
    expect(other.reload).to be_persisted
  end

  it "escapes user HTML and rejects an oversized character bible" do
    personality = create(:personality, :active, user: user, name: "<script>alert(1)</script>")
    sign_in

    get personality_path(personality)
    expect(response.body).not_to include("<script>alert(1)</script>")
    expect(response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")

    patch personality_path(personality), params: {
      personality: { name: personality.name, character_bible: "a" * 50_001 }
    }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "deletes personality data and queues stored object removal" do
    personality = create(:personality, :active, user: user)
    thread = create(:conversation_thread, personality: personality)
    message = create(:message, conversation_thread: thread)
    run = create(:generation_run, conversation_thread: thread, user_message: message)
    memory = create(:memory, personality: personality)
    relationship = create(:relationship_state, personality: personality)
    relationship_version = create(:relationship_state_version, relationship_state: relationship)
    summary_version = ThreadSummaryVersion.create!(conversation_thread: thread, generation_run: run,
                                                   through_message: message, source_message_ids: [ message.id ],
                                                   summary: "Private summary", revision: 1)
    attempt = create(:initiative_attempt, personality: personality, conversation_thread: thread,
                                          source_message: message)
    usage = create(:model_call, user: user, personality: personality, generation_run: run)
    create(:message_attachment, message: message, object_key: "uploads/privacy-test")
    Outbox::Publish.call(event_key: "generate-reply:#{run.id}", job_class: Ai::GenerateReplyJob,
                         arguments: [ run.id ])
    sign_in

    delete personality_path(personality)

    expect(response).to redirect_to(personalities_path)
    expect(Personality.exists?(personality.id)).to be(false)
    expect(ConversationThread.exists?(thread.id)).to be(false)
    expect(Message.exists?(message.id)).to be(false)
    expect(GenerationRun.exists?(run.id)).to be(false)
    expect(Memory.exists?(memory.id)).to be(false)
    expect(RelationshipStateVersion.exists?(relationship_version.id)).to be(false)
    expect(ThreadSummaryVersion.exists?(summary_version.id)).to be(false)
    expect(InitiativeAttempt.exists?(attempt.id)).to be(false)
    expect(usage.reload).to have_attributes(personality_id: nil, generation_run_id: nil)
    expect(OutboxEvent.where(event_key: "generate-reply:#{run.id}")).not_to exist
    expect(OutboxEvent.where(job_class: "ObjectStorage::DeleteObjectJob").exists?).to be(true)
  end

  it "deletes a personality with a ready avatar" do
    personality = create(:personality, :active, user: user)
    personality.update!(avatar_status: :ready, avatar_object_key: "avatars/ready.jpg",
                        avatar_content_type: "image/jpeg", avatar_byte_size: 123,
                        avatar_generated_at: Time.current,
                        avatar_source_version: personality.current_version)
    sign_in

    delete personality_path(personality)

    expect(response).to redirect_to(personalities_path)
    expect(Personality.exists?(personality.id)).to be(false)
    expect(OutboxEvent.where(job_class: "ObjectStorage::DeleteObjectJob").pluck(:arguments))
      .to include([ "avatars/ready.jpg" ])
  end

  it "deletes the account and all identifiable usage" do
    personality = create(:personality, :active, user: user)
    usage = create(:model_call, user: user, personality: personality)
    audit = AdminAuditEvent.create!(actor_user_id: user.id, action: "show", target_type: "User", target_id: user.id)
    sign_in

    delete account_path

    expect(response).to redirect_to(root_path)
    expect(User.exists?(user.id)).to be(false)
    expect(ModelCall.exists?(usage.id)).to be(false)
    expect(AdminAuditEvent.exists?(audit.id)).to be(false)
  end

  it "requires authentication for the export" do
    get data_export_path

    expect(response).to redirect_to(root_path)
  end
end
