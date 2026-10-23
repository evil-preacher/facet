require "rails_helper"

RSpec.describe "Locale switching", type: :request do
  it "uses English by default in tests" do
    get root_path

    expect(response.body).to include('<html lang="en">')
    expect(response.body).to include("Create a personality worth talking to")
  end

  it "switches to English and remembers the selection" do
    post locale_path(locale: "en")
    follow_redirect!

    expect(response.body).to include('<html lang="en">')
    expect(response.body).to include("Create a personality worth talking to")

    get root_path
    expect(response.body).to include("Send login code")
  end

  it "switches to Russian and renders localized content" do
    post locale_path(locale: "ru")
    follow_redirect!

    expect(response.body).to include('<html lang="ru">')
    expect(response.body).to include(I18n.t("app.home.heading", locale: :ru))
  end

  it "ignores unsupported locales" do
    post locale_path(locale: "fr")
    follow_redirect!

    expect(response.body).to include('<html lang="en">')
  end

  it "sends localized registration emails" do
    post locale_path(locale: "en")

    expect do
      post registration_path, params: { registration: { email: "english@example.com" } }
    end.to change(ActionMailer::Base.deliveries, :count).by(1)

    expect(ActionMailer::Base.deliveries.last.subject).to eq("Confirm your email for Facet")
    expect(flash[:notice]).to eq("If the address is available for registration, we sent a confirmation link.")
  end
end
