require "rails_helper"

RSpec.describe "Sidekiq operations UI", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPERATIONS_USERNAME").and_return("operator")
    allow(ENV).to receive(:[]).with("OPERATIONS_PASSWORD").and_return("secret")
  end

  it "is not exposed when operational credentials are absent" do
    allow(ENV).to receive(:[]).with("OPERATIONS_USERNAME").and_return(nil)
    allow(ENV).to receive(:[]).with("OPERATIONS_PASSWORD").and_return(nil)

    get "/operations/sidekiq/"

    expect(response).to have_http_status(:not_found)
  end

  it "requires HTTP basic authentication" do
    get "/operations/sidekiq/"

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers.fetch("WWW-Authenticate")).to include("Facet operations")
  end

  it "renders the dashboard for an operator" do
    get "/operations/sidekiq/",
        headers: {
          "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
            "operator", "secret"
          )
        }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sidekiq")
  end
end
