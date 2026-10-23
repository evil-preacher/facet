require "rails_helper"

RSpec.describe "Admin AI prompts", type: :request do
  let(:admin) { create(:user, :confirmed, admin: true) }

  def sign_in(user)
    challenge, code = LoginChallenge.issue_for!(user: user, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  it "restricts prompt publication to administrators" do
    post publish_admin_prompt_template_path("thread_summary"), params: { content: "New rules" }
    expect(response).to have_http_status(:not_found)

    sign_in(create(:user, :confirmed))
    get admin_prompt_templates_path
    expect(response).to have_http_status(:not_found)
    post publish_admin_prompt_template_path("thread_summary"), params: { content: "New rules" }
    expect(response).to have_http_status(:not_found)
    expect(AiPromptRevision.active.count).to eq(Ai::PromptCatalog::KEYS.length)
  end

  it "opens both prompt lists and audits them without a record ID" do
    sign_in(admin)

    get admin_prompt_templates_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("thread_summary")

    get admin_platform_prompts_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("mistral")

    expect(AdminAuditEvent.where(actor_user_id: admin.id, action: "index").pluck(:target_type, :target_id))
      .to include([ "AiPromptRevision", nil ], [ "AiPlatformPrompt", nil ])
  end

  it "publishes, reads, and restores immutable revisions with an audit trail" do
    sign_in(admin)
    get admin_prompt_template_path("thread_summary")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Test Thread summary")

    post publish_admin_prompt_template_path("thread_summary"), params: { content: "First summary rule" }
    first = AiPromptRevision.active.find_by!(key: "thread_summary")
    expect(first).to have_attributes(revision: 2, content: "First summary rule", published_by: admin)
    expect(Ai::PromptCatalog.content("thread_summary")).to eq("First summary rule")

    post publish_admin_prompt_template_path("thread_summary"), params: { content: "Second summary rule" }
    expect(first.reload).to be_status_retired
    expect(AiPromptRevision.active.find_by!(key: "thread_summary").revision).to eq(3)

    post restore_admin_prompt_template_path("thread_summary"), params: { revision_id: first.id }
    expect(AiPromptRevision.active.find_by!(key: "thread_summary")).to have_attributes(revision: 4, content: "First summary rule")
    expect(AdminAuditEvent.where(action: "publish_prompt", actor_user_id: admin.id).count).to eq(3)
  end

  it "rejects unknown template variables without changing the active revision" do
    sign_in(admin)
    post publish_admin_prompt_template_path("avatar_image"), params: { content: "{{unknown}}" }
    expect(response).to have_http_status(:unprocessable_content)
    post publish_admin_prompt_template_path("avatar_image"), params: { content: "{{character_name}}" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(AiPromptRevision.active.count).to eq(Ai::PromptCatalog::KEYS.length)
    expect(Ai::PromptCatalog.render("avatar_image", character_name: "Ada", character_context: "blue coat"))
      .to include("Ada", "blue coat")
  end

  it "renders published templates with their allowed variables" do
    sign_in(admin)
    post publish_admin_prompt_template_path("avatar_image"),
         params: { content: "Portrait of {{character_name}}. Context: {{character_context}}" }

    expect(response).to redirect_to(admin_prompt_template_path("avatar_image"))
    expect(Ai::PromptCatalog.render("avatar_image", character_name: "Ada", character_context: "blue coat"))
      .to eq("Portrait of Ada. Context: blue coat")
  end

  it "lets an admin publish provider corrections" do
    sign_in(admin)
    post publish_admin_platform_prompt_path("mistral"), params: { content: "Provider guidance" }
    expect(response).to redirect_to(admin_platform_prompt_path("mistral"))
    revision = AiPlatformPrompt.active_for(provider: "mistral")
    expect(revision.content).to eq("Provider guidance")
    expect(AdminAuditEvent.last).to have_attributes(action: "publish_platform_prompt", target_id: revision.id)
  end
end
