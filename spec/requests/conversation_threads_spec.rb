require "rails_helper"

RSpec.describe "Conversation threads", type: :request do
  let(:user) { create(:user, :confirmed) }
  let!(:profile) { create(:profile, user: user) }
  let(:personality) { create(:personality, :active, user: user) }

  def sign_in(user_to_sign_in = user)
    challenge, code = LoginChallenge.issue_for!(user: user_to_sign_in, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  def create_thread(owner_personality = personality, content: "First message")
    ConversationThreads::Create.call(
      personality: owner_personality,
      user: owner_personality.user,
      attributes: { content: content, client_token: SecureRandom.uuid }
    ).conversation_thread
  end

  it "requires authentication" do
    get personality_conversation_threads_path(personality)

    expect(response).to redirect_to(root_path)
  end

  it "lists only threads of the scoped personality" do
    own_thread = create_thread
    second_personality = create(:personality, :active, user: user)
    other_thread = create_thread(second_personality, content: "Another thread")
    sign_in

    get personality_conversation_threads_path(personality)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_thread.title)
    expect(response.body).to include("conversation-threads", "data-context-navigation")
    expect(response.body).to include(%(href="#{personality_path(personality)}"))
    expect(response.body).not_to include(other_thread.title)
  end

  it "creates a thread with its first message without accepting user ownership" do
    sign_in

    expect do
      post personality_conversation_threads_path(personality), params: {
        conversation_thread: {
          content: "Shall we discuss memory?",
          client_token: SecureRandom.uuid,
          user_id: create(:user).id
        }
      }
    end.to change(personality.conversation_threads, :count).by(1)
      .and change(Message, :count).by(2)

    thread = personality.conversation_threads.order(:created_at).last
    expect(response).to redirect_to(personality_conversation_thread_path(personality, thread))
    expect(thread.title).to eq("Shall we discuss memory?")
    expect(thread.messages.user.sole.content).to eq("Shall we discuss memory?")
  end

  it "renders validation errors for an empty first message" do
    sign_in

    expect do
      post personality_conversation_threads_path(personality), params: {
        conversation_thread: { content: " ", client_token: SecureRandom.uuid }
      }
    end.not_to change(ConversationThread, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Please review the message")
  end

  it "shows messages in their stable position order" do
    thread = create_thread
    Messages::Create.call(
      conversation_thread: thread,
      user: user,
      attributes: { content: "Second message", client_token: SecureRandom.uuid }
    )
    sign_in

    get personality_conversation_thread_path(personality, thread)

    expect(response.body).to include("conversation-active", "data-context-navigation")
    expect(response.body).to include(
      %(href="#{personality_path(personality)}"),
      %(href="#{personality_conversation_threads_path(personality)}")
    )
    expect(response.body.index("First message")).to be < response.body.index("Second message")
    expect(response.body).to match(
      /data-message-author>\s*#{Regexp.escape(personality.name)}\s*</
    )
  end

  it "archives an active conversation from the list" do
    thread = create_thread
    sign_in

    get personality_conversation_threads_path(personality)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(form[action="#{archive_personality_conversation_thread_path(personality, thread)}"]))).to be_present

    patch archive_personality_conversation_thread_path(personality, thread)

    expect(response).to redirect_to(personality_conversation_threads_path(personality))
    expect(thread.reload).to be_archived

    get personality_conversation_threads_path(personality)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(%(form[action="#{archive_personality_conversation_thread_path(personality, thread)}"]))).to be_nil
  end

  it "shows the actual response model and usage when AI debug UI is enabled" do
    previous_debug_ui = Rails.configuration.x.ai.debug_ui
    Rails.configuration.x.ai.debug_ui = true
    thread = create_thread
    generation_run = thread.generation_runs.first
    generation_run.assistant_message.update!(status: :completed, content: "Reply")
    generation_run.update!(status: :completed, completed_at: Time.current)
    create(
      :model_call,
      user: user,
      personality: personality,
      generation_run: generation_run,
      status: :completed,
      response_model: "gpt-4o-2024-11-20",
      input_tokens: 437,
      cached_input_tokens: 0,
      output_tokens: 42,
      cost_microusd: 1_000,
      pricing_version: "2026-09",
      completed_at: Time.current
    )
    create(
      :model_call,
      user: user,
      personality: personality,
      generation_run: generation_run,
      purpose: :memory_consolidation,
      status: :completed,
      response_model: "mistral-small-latest",
      input_tokens: 730,
      cached_input_tokens: 0,
      output_tokens: 19,
      cost_microusd: 100,
      pricing_version: "2026-09",
      completed_at: Time.current
    )
    sign_in

    get personality_conversation_thread_path(personality, thread)

    expect(response.body).to include("gpt-4o-2024-11-20 · 437 in / 42 out")
    expect(response.body).not_to include("mistral-small-latest · 730 in / 19 out")
  ensure
    Rails.configuration.x.ai.debug_ui = previous_debug_ui
  end

  it "archives a thread while preserving its messages" do
    thread = create_thread
    sign_in

    expect do
      patch archive_personality_conversation_thread_path(personality, thread)
    end.not_to change(Message, :count)

    expect(response).to redirect_to(personality_conversation_threads_path(personality))
    expect(thread.reload).to be_archived
    expect(thread.messages).to exist
  end

  it "does not expose another user's thread" do
    other_user = create(:user, :confirmed)
    create(:profile, user: other_user)
    other_personality = create(:personality, :active, user: other_user)
    other_thread = create_thread(other_personality)
    sign_in

    get personality_conversation_thread_path(other_personality, other_thread)
    expect(response).to have_http_status(:not_found)

    expect do
      patch archive_personality_conversation_thread_path(other_personality, other_thread)
    end.not_to change(other_thread, :status)
    expect(response).to have_http_status(:not_found)
  end
end
