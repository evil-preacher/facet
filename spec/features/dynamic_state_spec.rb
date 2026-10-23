require "rails_helper"

RSpec.describe "Dynamic state control", type: :feature do
  scenario "the owner enables dynamic state and can reset it" do
    user = create(:user, :confirmed)
    create(:profile, user: user)
    personality = create(:personality, :active, user: user, name: "Alice")

    visit root_path
    fill_in "login_email", with: user.email
    click_button "Send login code"
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
    fill_in "login_code", with: code
    click_button "Sign in"
    click_link "Alice"
    check "Allow dynamic state"
    click_button "Save", exact: true
    expect(personality.reload.dynamic_state_enabled?).to be(true)

    personality.create_relationship_state!(trust: 70)
    click_button "Reset state"
    expect(personality.relationship_state.reload.trust).to eq(50)
    expect(page).to have_content("Dynamic state reset")
  end
end
