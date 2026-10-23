require "rails_helper"

RSpec.describe "Administration", type: :feature do
  scenario "an administrator signs in and disables initiative" do
    admin = create(:user, :confirmed, admin: true)
    create(:profile, user: admin)
    personality = create(:personality, :active, name: "Visible personality", initiative_enabled: true)

    visit root_path
    fill_in "login_email", with: admin.email
    click_button "Send login code"
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
    fill_in "login_code", with: code
    click_button "Sign in"

    click_link "Administration"
    expect(page).to have_content("Administration")
    click_link "Personalities"
    click_link "Visible personality"
    click_button "Disable initiative"

    expect(page).to have_content("Initiative disabled")
    expect(personality.reload.initiative_enabled?).to be(false)
  end
end
