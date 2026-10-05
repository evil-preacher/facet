require "rails_helper"

RSpec.describe "Operations observability", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPERATIONS_USERNAME").and_return("operator")
    allow(ENV).to receive(:[]).with("OPERATIONS_PASSWORD").and_return("secret")
  end

  def authorization
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("operator", "secret") }
  end

  it "keeps metrics and diagnostics private" do
    get operations_metrics_path
    expect(response).to have_http_status(:unauthorized)

    get operations_diagnostics_path
    expect(response).to have_http_status(:unauthorized)
  end

  it "aggregates model usage without conversation content" do
    run = create(:generation_run, prompt_manifest: { "first_token_latency_ms" => 75 })
    call = create(:model_call, generation_run: run, personality: run.conversation_thread.personality,
                 user: run.conversation_thread.personality.user)
    call.update!(status: :completed, input_tokens: 100, cached_input_tokens: 20,
                 output_tokens: 10, cost_microusd: 300, pricing_version: "test",
                 completed_at: Time.current, latency_ms: 120)
    allow(Sidekiq::Queue).to receive(:all).and_return([])

    get operations_metrics_path, headers: authorization

    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch("model_calls").first
    expect(row).to include("input_tokens" => 100, "cached_ratio" => 0.2,
                           "average_first_token_ms" => 75,
                           "cost_microusd" => 300, "average_latency_ms" => 120)
    expect(response.body).not_to include("content", "prompt")
  end

  it "shows stale runs and only retries pending ones" do
    pending_run = create(:generation_run)
    pending_run.update_columns(created_at: 10.minutes.ago)
    running_run = create(:generation_run, status: :running, started_at: 20.minutes.ago)
    job = instance_double(Ai::GenerateReplyJob, job_id: "retry-1")
    allow(Ai::GenerateReplyJob).to receive(:perform_later).and_return(job)

    get operations_diagnostics_path, headers: authorization
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("pending_runs").pluck("id")).to include(pending_run.id)
    expect(response.parsed_body.fetch("running_runs").pluck("id")).to include(running_run.id)

    post operations_retry_run_path(id: pending_run.id), headers: authorization
    expect(response).to have_http_status(:accepted)
    expect(Ai::GenerateReplyJob).to have_received(:perform_later).with(pending_run.id)

    post operations_retry_run_path(id: running_run.id), headers: authorization
    expect(response).to have_http_status(:not_found)
  end
end
