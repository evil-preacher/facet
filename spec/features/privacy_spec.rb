require "rails_helper"

RSpec.describe "Privacy controls", type: :feature do
  scenario "a user finds the export and removes a personality" do
    user = create(:user, :confirmed)
    create(:profile, user: user)
    personality = create(:personality, :active, user: user, name: "Alice")

    visit root_path
    fill_in "login_email", with: user.email
    click_button "Send login code"
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
    fill_in "login_code", with: code
    click_button "Sign in"

    visit profile_path
    expect(page).to have_link("Download my data", href: data_export_path)

    visit personality_path(personality)
    click_button "Delete personality and all its data"

    expect(page).to have_content("Personality and its data deleted")
    expect(Personality.exists?(personality.id)).to be(false)
  end
end
