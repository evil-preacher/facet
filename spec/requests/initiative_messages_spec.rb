require "rails_helper"

RSpec.describe "Initiative messages", type: :request do
  let(:user) { create(:user, :confirmed) }
  let(:personality) { create(:personality, :active, user: user) }
  let(:thread) { create(:conversation_thread, personality: personality) }

  def sign_in(account = user)
    challenge, code = LoginChallenge.issue_for!(user: account, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  it "lets the owner enable initiative and rejects unsafe intervals" do
    create(:profile, user: user)
    sign_in

    patch initiative_settings_personality_path(personality), params: {
      personality: { initiative_enabled: "1", initiative_idle_hours: "48", initiative_cooldown_hours: "168" }
    }
    expect(response).to redirect_to(personality_path(personality))
    expect(personality.reload).to have_attributes(initiative_enabled: true,
                                                initiative_idle_hours: 48, initiative_cooldown_hours: 168)

    patch initiative_settings_personality_path(personality), params: {
      personality: { initiative_idle_hours: "1" }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(personality.reload.initiative_idle_hours).to eq(48)
  end

  it "does not allow another user to change the settings" do
    create(:profile, user: user)
    other = create(:user, :confirmed)
    create(:profile, user: other)
    sign_in(other)
    patch initiative_settings_personality_path(personality), params: {
      personality: { initiative_enabled: "1" }
    }
    expect(response).to have_http_status(:not_found)
    expect(personality.reload.initiative_enabled?).to be(false)
  end

  it "lets the owner choose intensity and quiet hours with a valid time zone" do
    create(:profile, user: user)
    sign_in

    patch initiative_settings_personality_path(personality), params: {
      personality: { initiative_enabled: "1", initiative_intensity: "normal",
                     initiative_timezone: "Almaty", initiative_quiet_start_hour: "23",
                     initiative_quiet_end_hour: "7" }
    }
    expect(response).to redirect_to(personality_path(personality))
    expect(personality.reload).to have_attributes(initiative_intensity: "normal",
                                                initiative_timezone: "Almaty",
                                                initiative_quiet_start_hour: 23,
                                                initiative_quiet_end_hour: 7)

    patch initiative_settings_personality_path(personality), params: {
      personality: { initiative_timezone: "Unknown/Place" }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(personality.reload.initiative_timezone).to eq("Almaty")
  end

  it "requires an explicit owner setting for email and can disable it immediately" do
    create(:profile, user: user)
    sign_in
    expect(personality.initiative_email_enabled?).to be(false)

    patch initiative_settings_personality_path(personality), params: {
      personality: { initiative_enabled: "1", initiative_email_enabled: "1" }
    }
    expect(response).to redirect_to(personality_path(personality))
    expect(personality.reload.initiative_email_enabled?).to be(true)

    patch initiative_settings_personality_path(personality), params: {
      personality: { initiative_email_enabled: "0" }
    }
    expect(personality.reload.initiative_email_enabled?).to be(false)

    other = create(:user, :confirmed)
    create(:profile, user: other)
    sign_in(other)
    patch initiative_settings_personality_path(personality), params: {
      personality: { initiative_email_enabled: "1" }
    }
    expect(response).to have_http_status(:not_found)
    expect(personality.reload.initiative_email_enabled?).to be(false)
  end

  it "shows unread counts and marks the thread read when opened" do
    create(:profile, user: user)
    message = create(:message, :assistant, conversation_thread: thread,
                     initiated_by: "personality", read_at: nil)
    sign_in

    get personalities_path
    expect(response.body).to include("Unread: 1")
    get personality_conversation_threads_path(personality)
    expect(response.body).to include("Unread: 1")
    get personality_conversation_thread_path(personality, thread)
    expect(response.body).to include("Wrote first")
    expect(message.reload.read_at).to be_present
    get personality_conversation_threads_path(personality)
    expect(response.body).not_to include("Unread: 1")
  end

  it "records owner feedback and stops initiative immediately after an intrusive report" do
    create(:profile, user: user)
    personality.update!(initiative_enabled: true, initiative_email_enabled: true)
    message = create(:message, :assistant, conversation_thread: thread, initiated_by: "personality")
    sign_in

    patch initiative_feedback_personality_conversation_thread_message_path(personality, thread, message),
          params: { initiative_feedback: "unwelcome" }

    expect(response).to redirect_to(personality_conversation_thread_path(personality, thread))
    expect(message.reload).to have_attributes(initiative_feedback: "unwelcome")
    expect(message.initiative_feedback_at).to be_present
    expect(personality.reload).to have_attributes(initiative_enabled: false, initiative_email_enabled: false)
    exported = DataExports::Build.call(user: user, storage: instance_double(ObjectStorage::S3Store))
    expect(exported.dig(:personalities, 0, :threads, 0, :messages, 0, :initiative_feedback)).to eq("unwelcome")
  end

  it "does not accept feedback on another owner's or a non-initiative message" do
    create(:profile, user: user)
    message = create(:message, :assistant, conversation_thread: thread, initiated_by: "personality")
    ordinary = create(:message, :assistant, conversation_thread: thread)
    other = create(:user, :confirmed)
    create(:profile, user: other)
    sign_in(other)

    patch initiative_feedback_personality_conversation_thread_message_path(personality, thread, message),
          params: { initiative_feedback: "unwelcome" }
    expect(response).to have_http_status(:not_found)
    expect(message.reload.initiative_feedback).to be_nil

    sign_in(user)
    patch initiative_feedback_personality_conversation_thread_message_path(personality, thread, ordinary),
          params: { initiative_feedback: "helpful" }
    expect(response).to have_http_status(:not_found)
  end
end
