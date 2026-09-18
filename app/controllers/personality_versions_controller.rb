class PersonalityVersionsController < ApplicationController
  before_action :require_authentication
  before_action :require_completed_profile
  before_action :set_personality
  before_action :set_version, only: :rollback

  def index
    @versions = @personality.versions
      .includes(:author, :source_version)
      .order(number: :desc)
  end

  def compare
    @from_version = @personality.versions.find(params.require(:from))
    @to_version = @personality.versions.find(params.require(:to))
    @diff = Personalities::VersionDiff.call(
      from_version: @from_version,
      to_version: @to_version
    )
  end

  def rollback
    result = Personalities::Rollback.call(
      personality: @personality,
      source_version: @version,
      author: current_user,
      change_note: t("app.personalities.versions.rollback_note", number: @version.number)
    )

    if result.success?
      redirect_to personality_path(@personality), notice: t(
        "app.flash.personality_rolled_back",
        number: result.version.number
      )
    else
      redirect_to personality_versions_path(@personality),
                  alert: result.errors.full_messages.to_sentence
    end
  end

  private

  def set_personality
    @personality = current_user.personalities.find(params[:personality_id])
  end

  def set_version
    @version = @personality.versions.find(params[:id])
  end
end
