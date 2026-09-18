require "rails_helper"

RSpec.describe "Registration", type: :request do
  it "renders the registration form in the authentication Turbo Frame" do
    get new_registration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(turbo-frame id="authentication"))
    expect(response.body).to include(%(data-turbo-frame="_top"))
  end

  it "creates an unconfirmed user and sends a confirmation link" do
    expect do
      post registration_path, params: { registration: { email: " New@Example.COM " } }
    end.to change(User, :count).by(1)
      .and change(ActionMailer::Base.deliveries, :count).by(1)

    user = User.last
    expect(user.email).to eq("new@example.com")
    expect(user).not_to be_confirmed
    expect(response).to redirect_to(root_path)
  end

  it "confirms the email and authenticates the user" do
    user = User.create!(email: "person@example.com")

    get email_confirmation_path(token: user.confirmation_token)

    expect(user.reload).to be_confirmed
    expect(response).to redirect_to(edit_profile_path)

    get edit_profile_path
    expect(response).to have_http_status(:ok)

    get email_confirmation_path(token: user.confirmation_token)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects an invalid confirmation link" do
    get email_confirmation_path(token: "invalid")

    expect(response).to have_http_status(:unprocessable_content)
  end
end
