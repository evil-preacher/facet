require "rails_helper"

RSpec.describe "Personalities", type: :request do
  let(:user) { create(:user, :confirmed) }
  let!(:profile) { create(:profile, user: user) }

  def sign_in(user_to_sign_in = user)
    challenge, code = LoginChallenge.issue_for!(user: user_to_sign_in, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  def create_personality_for(owner, name: "Alice")
    result = Personalities::Create.call(
      user: owner,
      attributes: {
        name: name,
        description: "Description",
        base_character: "Curious and independent.",
        communication_style: "Speaks naturally."
      }
    )
    result.personality
  end

  it "requires authentication" do
    get personalities_path

    expect(response).to redirect_to(root_path)
  end

  it "lists only the current user's personalities" do
    own_personality = create_personality_for(user)
    another_user = create(:user, :confirmed)
    create(:profile, user: another_user)
    other_personality = create_personality_for(another_user, name: "Another person's personality")
    sign_in

    get personalities_path

    expect(response.body).to include(own_personality.name)
    expect(response.body).not_to include(other_personality.name)
  end

  it "does not expose another user's personality" do
    another_user = create(:user, :confirmed)
    create(:profile, user: another_user)
    other_personality = create_personality_for(another_user)
    sign_in

    get personality_path(other_personality)

    expect(response).to have_http_status(:not_found)
  end

  it "renders validation errors without creating partial records" do
    sign_in

    expect do
      post personalities_path, params: {
        personality: { name: "", base_character: "", communication_style: "" }
      }
    end.not_to change(Personality, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Please review the form")
  end

  it "renders route-specific personality artwork" do
    personality = create_personality_for(user)
    sign_in

    get personalities_path
    expect(response.body).to include("personality-collection")

    get personality_path(personality)
    expect(response.body).to include("personality-detail", "data-context-navigation")
    expect(response.body.index("data-context-navigation")).to be <
      response.body.index(personality.current_version.content)
    expect(response.body).to include('max-h-[36rem] overflow-y-auto', 'tabindex="0"')

    get new_personality_path
    expect(response.body).to include("personality-creation")

    get edit_personality_path(personality)
    expect(response.body).to include("personality-creation")
  end

  it "shows the current relationship state on its personality page" do
    personality = create_personality_for(user)
    personality.create_relationship_state!(summary: "They trust each other more now.", revision: 3)
    sign_in

    get personality_path(personality)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Relationship state", "They trust each other more now.", "Version 3")
    expect(response.body).to include('href="#relationship-state"')
  end

  it "shows an empty relationship state when no summary exists" do
    personality = create_personality_for(user)
    sign_in

    get personality_path(personality)

    expect(response.body).to include("No established relationship context yet.")
  end

  it "updates metadata and the full character bible" do
    personality = create_personality_for(user)
    sign_in

    expect do
      patch personality_path(personality), params: {
        personality: {
          name: "Alice IX",
          description: "Updated description",
          character_bible: "# Character\n\nUpdated"
        }
      }
    end.to change(personality.versions, :count).by(1)

    expect(response).to redirect_to(personality_path(personality))
    expect(personality.reload.name).to eq("Alice IX")
    expect(personality.current_version.content).to include("Updated")
  end

  it "archives a personality without deleting its history" do
    personality = create_personality_for(user)
    sign_in

    expect do
      patch archive_personality_path(personality)
    end.not_to change(Personality, :count)

    expect(response).to redirect_to(personalities_path)
    expect(personality.reload).to be_archived
    expect(personality.versions).to exist
  end
  it "requires a completed profile" do
    profile.destroy!
    sign_in

    get new_personality_path

    expect(response).to redirect_to(edit_profile_path)
  end

  it "renders the creation wizard in the selected locale" do
    post locale_path(locale: "en")
    sign_in

    get new_personality_path

    expect(response.body).to include("Create your first personality")
    expect(response.body).to include("Conversational style")
  end
end
