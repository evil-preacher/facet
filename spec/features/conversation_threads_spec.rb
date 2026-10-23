require "rails_helper"

RSpec.describe "Conversation threads", type: :feature do
  scenario "a user creates messages, navigates between threads, and archives one" do
    user = create(:user, :confirmed)
    create(:profile, user: user)
    personality = Personalities::Create.call(
      user: user,
      attributes: {
        name: "Alice",
        base_character: "Curious.",
        communication_style: "Speaks naturally."
      }
    ).personality

    visit root_path
    fill_in "login_email", with: user.email
    click_button "Send login code"

    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
    fill_in "login_code", with: code
    click_button "Sign in"

    click_link "Alice"
    click_link "Conversations"
    expect(page).to have_css(%(img[src*="conversation-threads"]))
    click_link "New conversation"

    expect(page).to have_css(%(img[src*="conversation-new"]))

    fill_in "First message", with: "Shall we discuss old cities?"
    click_button "Start conversation"

    expect(page).to have_css("h1", text: "Shall we discuss old cities?")
    expect(page).to have_css(%(img[src*="conversation-active"]))
    expect(page).to have_content("Shall we discuss old cities?")

    fill_in "message_content", with: "Especially cities in the rain."
    click_button "Send"

    expect(page).to have_content("Especially cities in the rain.")
    first_thread = personality.conversation_threads.order(:created_at).first
    expect(first_thread.messages.user.order(:position).pluck(:position)).to eq([ 1, 3 ])
    expect(first_thread.messages.assistant.count).to eq(2)

    click_link "All conversations"
    click_link "New conversation"
    fill_in "First message", with: "Shall we discuss science fiction?"
    click_button "Start conversation"

    expect(page).to have_css("h1", text: "Shall we discuss science fiction?")
    click_link "Shall we discuss old cities?"
    expect(page).to have_content("Especially cities in the rain.")

    click_button "Archive"

    expect(page).to have_content("Conversation archived.")
    click_link "Shall we discuss old cities?"
    expect(page).to have_content("This thread is archived")
    expect(page).not_to have_button("Send")
    expect(first_thread.reload).to be_archived
  end
end
