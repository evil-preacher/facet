require "rails_helper"

RSpec.describe "Notifications", type: :request do
  let(:user) { create(:user, :confirmed) }

  def sign_in(account = user)
    challenge, code = LoginChallenge.issue_for!(user: account, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  it "requires authentication" do
    get notifications_path
    expect(response).to redirect_to(root_path)
  end

  it "lists only the owner's unread threads and clears a thread after opening it" do
    create(:profile, user: user)
    personality = create(:personality, :active, user: user, name: "Alice")
    first_thread = create(:conversation_thread, personality: personality, title: "First thread")
    second_thread = create(:conversation_thread, personality: personality, title: "Second thread")
    first_message = create(:message, :assistant, conversation_thread: first_thread,
                           content: "How is your day going?", initiated_by: "personality")
    create(:message, :assistant, conversation_thread: first_thread,
           content: "One more thought", initiated_by: "personality")
    create(:message, :assistant, conversation_thread: second_thread,
           content: "Hello again", initiated_by: "personality")
    other_thread = create(:conversation_thread)
    create(:message, :assistant, conversation_thread: other_thread,
           content: "Another person's message", initiated_by: "personality")
    sign_in

    get notifications_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("First thread", "Second thread", "One more thought", "Unread: 2")
    expect(response.body).to include("unread conversations: 2")
    expect(response.body).not_to include("Another person's message")

    get personality_conversation_thread_path(personality, first_thread)
    expect(first_message.reload.read_at).to be_present
    get notifications_path
    expect(response.body).not_to include("First thread")
    expect(response.body).to include("Second thread", "unread conversations: 1")
  end

  it "shows an empty state when everything is read" do
    sign_in
    get notifications_path
    expect(response.body).to include("No new messages yet")
  end
end
