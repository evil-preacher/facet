require "rails_helper"

RSpec.describe "Authentication", type: :feature do
  scenario "a visitor registers, confirms their email, and completes a profile" do
    email = FFaker::Internet.email

    visit root_path
    expect(page).to have_no_field("registration_email")
    click_link "Register"
    fill_in "registration_email", with: email
    click_button "Send confirmation link"

    expect(page).to have_content("we sent a confirmation link")
    expect(User.find_by!(email: email)).not_to be_confirmed

    confirmation_url = ActionMailer::Base.deliveries.last.text_part.body.decoded.lines
                                               .find { |line| line.start_with?("http") }
                                               .strip
    visit URI(confirmation_url).request_uri

    expect(page).to have_content("Email confirmed")
    fill_in "profile_first_name", with: "Anna"
    fill_in "profile_last_name", with: "Johnson"
    select "Female", from: "profile_gender"
    fill_in "profile_birth_date", with: "1990-05-10"
    click_button "Save profile"

    expect(page).to have_css("h1", text: "Create your first personality")
    expect(User.find_by!(email: email).profile).to have_attributes(
      first_name: "Anna", last_name: "Johnson"
    )
  end

  scenario "a confirmed user signs in with an emailed OTP and signs out" do
    profile = create(:profile, first_name: "John", last_name: "Smith", gender: :male)

    visit root_path
    fill_in "login_email", with: profile.user.email
    click_button "Send login code"

    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
    fill_in "login_code", with: code
    click_button "Sign in"

    expect(page).to have_css("h1", text: "Create your first personality")
    click_button "Log out"
    expect(page).to have_content("You are signed out")
    expect(page).to have_button("Send login code")
  end

  scenario "a visitor switches the interface to English" do
    visit root_path
    click_button "EN"

    expect(page).to have_css("html[lang='en']", visible: :all)
    expect(page).to have_content("Create a personality worth talking to")
    expect(page).to have_button("Send login code")
  end
end
