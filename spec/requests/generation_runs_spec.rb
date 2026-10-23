require "rails_helper"

RSpec.describe "Generation runs", type: :request do
  let(:user) { create(:user, :confirmed) }
  let!(:profile) { create(:profile, user: user) }
  let(:personality) { create(:personality, :active, user: user) }
  let(:conversation_thread) { create(:conversation_thread, personality: personality) }
  let(:user_message) { create(:message, conversation_thread: conversation_thread) }
  let(:generation_run) do
    create(
      :generation_run,
      conversation_thread: conversation_thread,
      personality_version: personality.current_version,
      user_message: user_message,
      status: :failed,
      error_message: "Provider timeout"
    )
  end

  def sign_in(user_to_sign_in = user)
    challenge, code = LoginChallenge.issue_for!(user: user_to_sign_in, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  it "renders generation failure and retries it" do
    generation_run
    sign_in

    get personality_conversation_thread_path(personality, conversation_thread)

    expect(response.body).to include("The reply could not be generated")
    expect(response.body).to include("Provider timeout")
    expect(response.body).to include("Retry")

    post retry_personality_conversation_thread_generation_run_path(
      personality,
      conversation_thread,
      generation_run
    )

    expect(response).to redirect_to(
      personality_conversation_thread_path(personality, conversation_thread)
    )
    expect(generation_run.reload).to be_failed
    expect(generation_run.retry_run).to be_pending
  end

  it "streams a completed reply as SSE from a reconnect cursor" do
    assistant = create(
      :message,
      :assistant,
      conversation_thread: conversation_thread,
      personality_version: personality.current_version,
      status: :completed,
      content: "Hello!"
    )
    generation_run.update!(
      assistant_message: assistant,
      status: :completed,
      completed_at: Time.current
    )
    sign_in

    get stream_personality_conversation_thread_generation_run_path(
      personality,
      conversation_thread,
      generation_run
    ), headers: { "Last-Event-ID" => "2" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/event-stream")
    expect(response.headers["X-Accel-Buffering"]).to eq("no")
    expect(response.body).to include("event: delta", "\"delta\":\"llo!\"", "event: done")
  end

  it "stops an active generation" do
    assistant = create(
      :message,
      :assistant,
      conversation_thread: conversation_thread,
      personality_version: personality.current_version,
      status: :streaming,
      content: ""
    )
    generation_run.update!(assistant_message: assistant, status: :running)
    sign_in

    post stop_personality_conversation_thread_generation_run_path(
      personality,
      conversation_thread,
      generation_run
    )

    expect(response).to redirect_to(
      personality_conversation_thread_path(personality, conversation_thread)
    )
    expect(generation_run.reload).to be_stopped
    expect(assistant.reload).to be_stopped
  end

  it "does not expose another user's run" do
    other_user = create(:user, :confirmed)
    create(:profile, user: other_user)
    other_personality = create(:personality, :active, user: other_user)
    other_thread = create(:conversation_thread, personality: other_personality)
    other_message = create(:message, conversation_thread: other_thread)
    other_run = create(
      :generation_run,
      conversation_thread: other_thread,
      personality_version: other_personality.current_version,
      user_message: other_message,
      status: :failed
    )
    sign_in

    expect do
      post retry_personality_conversation_thread_generation_run_path(
        other_personality,
        other_thread,
        other_run
      )
    end.not_to change(other_run, :status)

    expect(response).to have_http_status(:not_found)
  end
end
