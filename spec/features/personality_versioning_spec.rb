require "rails_helper"

RSpec.describe "Personality versioning", type: :feature do
  scenario "a user compares versions and restores an earlier character bible" do
    user = create(:user, :confirmed)
    create(:profile, user: user)
    personality = Personalities::Create.call(
      user: user,
      attributes: {
        name: "Alice",
        base_character: "Warm and curious.",
        communication_style: "Speaks naturally."
      }
    ).personality
    first_version = personality.current_version
    Personalities::Update.call(
      personality: personality,
      author: user,
      attributes: {
        name: personality.name,
        description: personality.description,
        character_bible: "# Character\n\nWarm but candid\nLikes rain",
        change_note: "Added candor and a love of rain"
      }
    )

    visit root_path
    fill_in "login_email", with: user.email
    click_button "Send login code"

    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
    fill_in "login_code", with: code
    click_button "Sign in"

    click_link "Alice"
    click_link "Version history"

    expect(page).to have_css("h1", text: "Alice version history")
    expect(page).to have_content("Added candor and a love of rain")
    expect(page).to have_content(user.email)

    select "Version 1", from: "From version"
    select "Version 2", from: "To version"
    click_button "Compare"

    expect(page).to have_css("h1", text: "Comparing versions 1 and 2")
    expect(page).to have_content("Warm but candid")

    click_link "Back to version history"
    within(find("article", text: "Version 1")) do
      click_button "Restore this version"
    end

    expect(page).to have_css("h1", text: "Alice")
    expect(page).to have_content("Version 3")
    expect(personality.reload.current_version).to have_attributes(
      content: first_version.content,
      source_version_id: first_version.id
    )
  end
end
