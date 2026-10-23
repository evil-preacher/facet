require "rails_helper"

RSpec.describe "Mixed-language conversation", type: :feature do
  scenario "the latest message controls prompt language in the same thread" do
    user = create(:user, :confirmed)
    create(:profile, user: user)
    personality = create(:personality, :active, user: user, name: "Alice")
    russian_message = I18n.t("app.flash.signed_in", locale: :ru)

    visit root_path
    fill_in "login_email", with: user.email
    click_button "Send login code"
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
    fill_in "login_code", with: code
    click_button "Sign in"

    visit new_personality_conversation_thread_path(personality)
    fill_in "First message", with: russian_message
    click_button "Start conversation"
    thread = personality.conversation_threads.last

    click_button "EN"
    expect(page).to have_button("Send")
    fill_in "message_content", with: "Hello, how are you today?"
    click_button "Send"

    messages = thread.messages.user.order(:position)
    expect(messages.pluck(:language)).to eq(%w[ru en])
    latest_run = thread.generation_runs.order(:created_at).last
    manifest = Ai::PromptBuilder.call(generation_run: latest_run).manifest
    expect(manifest.fetch("detected_language")).to eq("en")
    expect(page).to have_content(russian_message)
    expect(page).to have_content("Hello, how are you today?")
  end
end
