require "rails_helper"

RSpec.describe "Profile", type: :request do
  let(:user) { User.create!(email: "person@example.com", confirmed_at: Time.current) }

  def sign_in
    challenge, code = LoginChallenge.issue_for!(user: user, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  it "requires authentication" do
    get profile_path

    expect(response).to redirect_to(root_path)
  end

  it "creates and displays a profile" do
    sign_in

    expect do
      patch profile_path, params: {
        profile: { first_name: "Anna", last_name: "Johnson", gender: "female", birth_date: "1990-05-10" }
      }
    end.to change(Profile, :count).by(1)

    expect(response).to redirect_to(new_personality_path)
    follow_redirect!
    expect(response.body).to include("Create your first personality")
  end
end
