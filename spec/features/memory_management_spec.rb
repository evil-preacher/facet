require "rails_helper"

RSpec.describe "Memory management", type: :feature do
  scenario "a user reviews, corrects, and deletes a personality memory" do
    user = create(:user, :confirmed)
    create(:profile, user: user)
    personality = create(:personality, :active, user: user, name: "Alice")
    memory = create(
      :memory,
      personality: personality,
      kind: :preference,
      content: "The user likes coffee",
      importance: 60
    )

    visit root_path
    fill_in "login_email", with: user.email
    click_button "Send login code"
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
    fill_in "login_code", with: code
    click_button "Sign in"

    click_link "Alice"
    click_link "Memory"

    expect(page).to have_css("h1", text: "What Alice remembers")
    expect(page).to have_content("The user likes coffee")
    expect(page).to have_content("Total memories: 1")
    expect(page).to have_link("Preference 1")

    fill_in "memory_content", with: "The user likes tea"
    fill_in "Importance", with: "80"
    click_button "Save correction"

    expect(page).to have_content("Memory updated")
    expect(page).to have_content("The user likes tea")
    expect(memory.reload).to be_superseded

    click_button "Delete"

    expect(page).to have_content("Memory deleted")
    expect(personality.memories.current).to be_empty
  end
end
