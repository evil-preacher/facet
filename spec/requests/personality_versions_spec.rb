require "rails_helper"

RSpec.describe "Personality versions", type: :request do
  let(:user) { create(:user, :confirmed) }
  let!(:profile) { create(:profile, user: user) }
  let(:personality) { create_personality_for(user) }

  def sign_in(user_to_sign_in = user)
    challenge, code = LoginChallenge.issue_for!(user: user_to_sign_in, requested_ip: "127.0.0.1")
    post verify_login_path, params: { login: { token: challenge.token, code: code } }
  end

  def create_personality_for(owner, name: "Alice")
    Personalities::Create.call(
      user: owner,
      attributes: {
        name: name,
        base_character: "Curious and independent.",
        communication_style: "Speaks naturally."
      }
    ).personality
  end

  def add_version(personality_to_update, content:, note:)
    Personalities::Update.call(
      personality: personality_to_update,
      author: personality_to_update.user,
      attributes: {
        name: personality_to_update.name,
        description: personality_to_update.description,
        character_bible: content,
        change_note: note
      }
    ).personality.current_version
  end

  it "shows history with author, date, and change note" do
    add_version(personality, content: "# Character\n\nWarm but candid", note: "Made the character more direct")
    sign_in

    get personality_versions_path(personality)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Version 2")
    expect(response.body).to include("personality-history")
    expect(response.body).to include("Made the character more direct")
    expect(response.body).to include(user.email)
  end

  it "renders a line-by-line comparison" do
    first_version = personality.current_version
    second_version = add_version(
      personality,
      content: "# Character\n\nWarm but candid\nLikes rain",
      note: "Clarified the character"
    )
    sign_in

    get compare_personality_versions_path(personality), params: {
      from: first_version.id,
      to: second_version.id
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Comparing versions 1 and 2")
    expect(response.body).to include("personality-comparison")
    expect(response.body).to include("Warm but candid")
    expect(response.body).to include("Likes rain")
  end

  it "rolls back by creating a new version" do
    first_version = personality.current_version
    add_version(personality, content: "# Changed", note: "Changed")
    sign_in

    expect do
      post rollback_personality_version_path(personality, first_version)
    end.to change(personality.versions, :count).by(1)

    expect(response).to redirect_to(personality_path(personality))
    expect(personality.reload.current_version).to have_attributes(
      number: 3,
      content: first_version.content,
      source_version_id: first_version.id,
      author: user
    )
  end

  it "does not expose another user's history, diff, or rollback" do
    other_user = create(:user, :confirmed)
    create(:profile, user: other_user)
    other_personality = create_personality_for(other_user, name: "Another person's")
    other_version = other_personality.current_version
    sign_in

    get personality_versions_path(other_personality)
    expect(response).to have_http_status(:not_found)

    get compare_personality_versions_path(other_personality), params: {
      from: other_version.id,
      to: other_version.id
    }
    expect(response).to have_http_status(:not_found)

    expect do
      post rollback_personality_version_path(other_personality, other_version)
    end.not_to change(PersonalityVersion, :count)
    expect(response).to have_http_status(:not_found)
  end
end
