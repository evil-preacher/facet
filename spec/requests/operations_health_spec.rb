require "rails_helper"

RSpec.describe "Operations health", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPERATIONS_USERNAME").and_return("operator")
    allow(ENV).to receive(:[]).with("OPERATIONS_PASSWORD").and_return("secret")
  end

  it "is not exposed when operational credentials are absent" do
    allow(ENV).to receive(:[]).with("OPERATIONS_USERNAME").and_return(nil)
    allow(ENV).to receive(:[]).with("OPERATIONS_PASSWORD").and_return(nil)

    get operations_health_path

    expect(response).to have_http_status(:not_found)
  end

  it "requires HTTP basic authentication" do
    get operations_health_path

    expect(response).to have_http_status(:unauthorized)
  end

  it "reports database, Redis, Sidekiq, and outbox state to an operator" do
    redis = double(call: "PONG")
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(Sidekiq::Stats).to receive(:new).and_return(
      double(processes_size: 1, enqueued: 2, scheduled_size: 3, retry_size: 4, dead_size: 5)
    )
    allow(Sidekiq::Queue).to receive(:all).and_return([])

    get operations_health_path,
        headers: {
          "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
            "operator", "secret"
          )
        }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "status" => "ok",
      "database" => "ok",
      "redis" => "ok",
      "outbox" => include("pending" => 0)
    )
    expect(response.parsed_body.fetch("sidekiq")).to include("retries" => 4, "dead" => 5)
  end
end
