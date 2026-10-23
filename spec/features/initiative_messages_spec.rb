require "rails_helper"

RSpec.describe "Initiative messages", type: :feature do
  scenario "the owner enables initiative, sees an unread message, and opens it" do
    user = create(:user, :confirmed)
    create(:profile, user: user)
    personality = create(:personality, :active, user: user, name: "Alice")
    thread = create(:conversation_thread, personality: personality, title: "Our conversation")
    message = create(:message, :assistant, conversation_thread: thread,
                     content: "Hello, how are you?", initiated_by: "personality", read_at: nil)

    visit root_path
    fill_in "login_email", with: user.email
    click_button "Send login code"
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
    fill_in "login_code", with: code
    click_button "Sign in"

    expect(page).to have_content("Unread: 1")
    find('a[aria-label="Messages, unread conversations: 1"]').click
    expect(page).to have_css("h1", text: "Messages")
    expect(page).to have_content("Our conversation")
    click_link "Personalities"
    click_link "Alice"
    check "Allow the personality to write first"
    check "Allow initiative messages to be emailed to me"
    click_button "Save settings"
    expect(personality.reload.initiative_enabled?).to be(true)
    expect(personality.initiative_email_enabled?).to be(true)
    click_link "Conversations"
    expect(page).to have_content("Unread: 1")
    click_link "Our conversation"
    expect(page).to have_content("Hello, how are you?")
    expect(message.reload.read_at).to be_present
  end
end
