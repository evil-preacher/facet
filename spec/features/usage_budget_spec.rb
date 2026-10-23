require "rails_helper"

RSpec.describe "Usage budget", type: :feature do
  scenario "a user sees their own spending and changes their monthly limit" do
    user = create(:user, :confirmed)
    create(:profile, user: user)
    create(:personality, :active, user: user)
    create(:model_call, user: user, status: :completed, cost_microusd: 1_250_000,
           input_tokens: 100, cached_input_tokens: 20, output_tokens: 50,
           pricing_version: "test", completed_at: Time.current)

    visit root_path
    fill_in "login_email", with: user.email
    click_button "Send login code"
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]
    fill_in "login_code", with: code
    click_button "Sign in"

    click_link "Usage"
    expect(page).to have_css("h1", text: "Usage and limits")
    expect(page).to have_content("1.2500")
    expect(page).to have_content("Messages")

    fill_in "Your limit, USD", with: "5"
    click_button "Save limit"
    expect(page).to have_content("Monthly limit updated")
    expect(user.reload.monthly_ai_limit_microusd).to eq(5_000_000)
  end
end
