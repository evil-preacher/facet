require "rails_helper"

RSpec.describe "Dynamic state settings", type: :request do
  let(:user) { create(:user, :confirmed) }
  let(:personality) { create(:personality, :active, user: user) }

  def sign_in(account = user)
    create(:profile, user: account)
    challenge, code = LoginChallenge.issue_for!(user: account, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  it "lets the owner enable, disable and reset state without changing initiative settings" do
    sign_in
    get personality_path(personality)
    expect(response.body).to include("Dynamic state")

    patch dynamic_state_settings_personality_path(personality), params: { personality: { dynamic_state_enabled: "1" } }
    expect(response).to redirect_to(personality_path(personality))
    expect(personality.reload.dynamic_state_enabled?).to be(true)
    expect(personality.initiative_enabled?).to be(false)

    personality.create_relationship_state!(trust: 70)
    post reset_dynamic_state_personality_path(personality)
    expect(personality.relationship_state.reload.trust).to eq(50)
    expect(personality.relationship_state.dynamic_revisions.last.event_kind).to eq("reset")

    patch dynamic_state_settings_personality_path(personality), params: { personality: { dynamic_state_enabled: "0" } }
    expect(personality.reload.dynamic_state_enabled?).to be(false)
  end

  it "rejects another user's setting and reset requests" do
    other = create(:user, :confirmed)
    sign_in(other)
    patch dynamic_state_settings_personality_path(personality), params: { personality: { dynamic_state_enabled: "1" } }
    expect(response).to have_http_status(:not_found)
    post reset_dynamic_state_personality_path(personality)
    expect(response).to have_http_status(:not_found)
    expect(personality.reload.dynamic_state_enabled?).to be(false)
  end
end
