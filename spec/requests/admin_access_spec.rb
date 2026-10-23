require "rails_helper"

RSpec.describe "Administration", type: :request do
  let(:admin) { create(:user, :confirmed, admin: true) }

  def sign_in(user)
    challenge, code = LoginChallenge.issue_for!(user: user, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  it "requires an administrator who signed in with an email code" do
    get admin_root_path
    expect(response).to have_http_status(:not_found)

    ordinary = create(:user, :confirmed)
    sign_in(ordinary)
    get admin_root_path
    expect(response).to have_http_status(:not_found)
    get admin_users_path
    expect(response).to have_http_status(:not_found)
    get admin_user_path(ordinary)
    expect(response).to have_http_status(:not_found)
    personality = create(:personality, :active, initiative_enabled: true)
    post disable_initiative_admin_personality_path(personality)
    expect(response).to have_http_status(:not_found)
    expect(personality.reload.initiative_enabled?).to be(true)

    ordinary.update!(admin: true)
    get admin_root_path
    expect(response).to have_http_status(:ok)
    expect(response.headers.fetch("Cache-Control")).to include("no-store")

    ordinary.update!(admin: false)
    get admin_root_path
    expect(response).to have_http_status(:not_found)
  end

  it "shows only approved metadata and audits index and record views" do
    personality = create(:personality, :active, user: admin, name: "Visible name")
    thread = create(:conversation_thread, personality: personality)
    create(:message, conversation_thread: thread, content: "PRIVATE MESSAGE TEXT")
    create(:memory, personality: personality, content: "PRIVATE MEMORY TEXT")
    run = create(:generation_run, conversation_thread: thread,
                 prompt_manifest: { secret: "PRIVATE MANIFEST TEXT" },
                 error_message: "PRIVATE PROVIDER ERROR")
    sign_in(admin)

    get admin_personalities_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visible name")
    expect(response.body).not_to include("PRIVATE MESSAGE TEXT", "PRIVATE MEMORY TEXT")

    get admin_generation_run_path(run)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("PRIVATE MANIFEST TEXT", "PRIVATE PROVIDER ERROR")

    get admin_user_path(admin)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Current monthly budget")
    expect(AdminAuditEvent.where(actor_user_id: admin.id).pluck(:action, :target_type, :target_id))
      .to include([ "index", "Personality", nil ], [ "show", "GenerationRun", run.id ])
  end

  it "shows the current Character Bible only on an authorized personality detail page" do
    personality = create(:personality, name: "Bible owner")
    version = create(:personality_version, personality: personality, number: 1,
                    content: "# Identity\n\nName: Ada <script>alert('x')</script>")
    personality.update!(current_version: version, status: :active)

    get admin_personality_path(personality)
    expect(response).to have_http_status(:not_found)

    sign_in(admin)
    get admin_personalities_path
    expect(response.body).not_to include("Name: Ada")

    get admin_personality_path(personality)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Character Bible", "v1", "Name: Ada &lt;script&gt;")
    expect(response.body).not_to include("Name: Ada <script>")
    expect(AdminAuditEvent.last).to have_attributes(action: "show", target_type: "Personality", target_id: personality.id)
  end

  it "offers only read routes, without generic update, delete, bulk or export" do
    patch "/admin/users/#{admin.id}", params: { user: { admin: false } }
    expect(response).to have_http_status(:not_found)
    delete "/admin/users/#{admin.id}"
    expect(response).to have_http_status(:not_found)
    get "/admin/messages"
    expect(response).to have_http_status(:not_found)
    get "/admin/users.csv"
    expect(response).not_to have_http_status(:ok)
    expect(admin.reload.admin?).to be(true)
  end

  it "disables initiative and records the actor without private content" do
    personality = create(:personality, :active, initiative_enabled: true)
    sign_in(admin)

    post disable_initiative_admin_personality_path(personality)

    expect(response).to redirect_to(admin_personality_path(personality))
    expect(personality.reload.initiative_enabled?).to be(false)
    expect(AdminAuditEvent.last).to have_attributes(actor_user_id: admin.id,
      action: "disable_initiative", target_type: "Personality", target_id: personality.id)
    expect(AdminAuditEvent.last.attributes.keys).not_to include("content", "details")
  end

  it "re-enqueues only old pending runs and audits success" do
    run = create(:generation_run)
    run.update_columns(created_at: 10.minutes.ago)
    running = create(:generation_run, status: :running, started_at: 20.minutes.ago)
    job = instance_double(Ai::GenerateReplyJob, job_id: "admin-retry")
    allow(Ai::GenerateReplyJob).to receive(:perform_later).and_return(job)
    sign_in(admin)

    post retry_pending_admin_generation_run_path(run)
    expect(response).to redirect_to(admin_generation_run_path(run))
    expect(Ai::GenerateReplyJob).to have_received(:perform_later).with(run.id)
    expect(AdminAuditEvent.where(action: "retry_pending", target_id: run.id)).to exist

    post retry_pending_admin_generation_run_path(running)
    expect(response).to have_http_status(:not_found)
    expect(AdminAuditEvent.where(action: "retry_pending", target_id: running.id)).not_to exist
  end
end
