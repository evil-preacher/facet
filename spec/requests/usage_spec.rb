require "rails_helper"

RSpec.describe "Usage", type: :request do
  let(:user) { create(:user, confirmed_at: Time.current) }

  def sign_in(account = user)
    challenge, code = LoginChallenge.issue_for!(user: account, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  it "requires authentication" do
    get usage_path
    expect(response).to redirect_to(root_path)
  end

  it "shows only the signed-in user's monthly usage" do
    sign_in
    create(:model_call, user: user, status: :completed, cost_microusd: 2_000_000,
           input_tokens: 100, cached_input_tokens: 20, output_tokens: 10,
           pricing_version: "test", completed_at: Time.current)
    create(:model_call, user: create(:user), status: :completed, cost_microusd: 9_000_000,
           input_tokens: 900, cached_input_tokens: 0, output_tokens: 100,
           pricing_version: "test", completed_at: Time.current)

    get usage_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Usage and limits", "2.0000", "100")
    expect(response.body).not_to include("9.0000")
  end

  it "updates the monthly limit and rejects invalid values" do
    sign_in
    patch usage_path, params: { monthly_limit_usd: "12.5" }
    expect(user.reload.monthly_ai_limit_microusd).to eq(12_500_000)

    patch usage_path, params: { monthly_limit_usd: "-1" }
    expect(user.reload.monthly_ai_limit_microusd).to eq(12_500_000)

    patch usage_path, params: { monthly_limit_usd: "NaN" }
    expect(user.reload.monthly_ai_limit_microusd).to eq(12_500_000)
  end
end
