require "rails_helper"

RSpec.describe "Personality onboarding", type: :feature do
  scenario "a new user creates their first personality after completing a profile" do
    user = create(:user, :confirmed)

    visit root_path
    fill_in "login_email", with: user.email
    click_button "Send login code"

    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
    fill_in "login_code", with: code
    click_button "Sign in"

    fill_in "profile_first_name", with: "Alex"
    fill_in "profile_last_name", with: "Smith"
    select "Prefer not to say", from: "profile_gender"
    click_button "Save profile"

    expect(page).to have_css("h1", text: "Create your first personality")
    expect(page).to have_css(%(img[src*="personality-creation"][aria-hidden="true"]))

    fill_in "personality_name", with: "Alice"
    fill_in "personality_description", with: "A companion for long conversations"
    fill_in "personality_base_character", with: "Warm and curious, but independent-minded."
    fill_in "personality_communication_style", with: "Speaks naturally without overexplaining."
    fill_in "personality_likes", with: "Dark fantasy, old cities, and rain."
    fill_in "personality_dislikes", with: "Corporate language and motivational cliches."
    fill_in "personality_relationship_context", with: "Has known Alex for years."
    fill_in "personality_allowed_behaviors", with: "Can disagree gently and joke."
    fill_in "personality_forbidden_behaviors", with: "Does not invent shared memories."
    click_button "Create personality"

    expect(page).to have_css("h1", text: "Alice")
    expect(page).to have_content("Warm and curious")
    expect(page).to have_content("Dark fantasy")
    expect(page).to have_content("Does not invent shared memories")

    personality = user.personalities.sole
    expect(personality.current_version.number).to eq(1)
    expect(personality.current_version.content).to include("Speaks naturally")
  end
end
