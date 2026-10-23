require "rails_helper"

RSpec.describe "Passwordless login", type: :request do
  let!(:user) { User.create!(email: "person@example.com", confirmed_at: Time.current) }

  it "emails an OTP and starts a session after verification" do
    expect do
      post login_path, params: { login: { email: user.email } }
    end.to change(LoginChallenge, :count).by(1)
      .and change(ActionMailer::Base.deliveries, :count).by(1)

    challenge = LoginChallenge.last
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b\d{6}\b/]

    post verify_login_path, params: { login: { token: challenge.token, code: code } }

    expect(response).to redirect_to(edit_profile_path)
    get edit_profile_path
    expect(response).to have_http_status(:ok)
  end

  it "does not disclose an unknown email" do
    expect do
      post login_path, params: { login: { email: "unknown@example.com" } }
    end.not_to change(LoginChallenge, :count)

    expect(response).to redirect_to(/login\/verify/)
    expect(flash[:notice]).to eq("If the account exists, a code was sent by email.")
  end

  it "rejects an incorrect code" do
    challenge, code = LoginChallenge.issue_for!(user: user, requested_ip: "127.0.0.1")
    wrong_code = code == "000000" ? "999999" : "000000"

    post verify_login_path, params: { login: { token: challenge.token, code: wrong_code } }

    expect(response).to have_http_status(:unprocessable_content)
  end
end
