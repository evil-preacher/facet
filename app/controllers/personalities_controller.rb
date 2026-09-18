class PersonalitiesController < ApplicationController
  before_action :require_authentication
  before_action :require_completed_profile
  before_action :set_personality, only: %i[show edit update archive]

  def index
    @personalities = current_user.personalities.order(
      Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'draft' THEN 1 ELSE 2 END"),
      updated_at: :desc
    )
  end

  def show
  end

  def new
    @first_personality = current_user.personalities.none?
    @form = Personalities::Create.new(user: current_user, attributes: {})
  end

  def create
    @form = Personalities::Create.call(user: current_user, attributes: create_params)

    if @form.success?
      redirect_to personality_path(@form.personality), notice: t("app.flash.personality_created")
    else
      @first_personality = current_user.personalities.none?
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    result = Personalities::Update.call(personality: @personality, attributes: update_params)

    if result.success?
      redirect_to personality_path(@personality), notice: t("app.flash.personality_updated")
    else
      @personality.assign_attributes(update_params.slice(:name, :description))
      @update_errors = result.errors
      render :edit, status: :unprocessable_content
    end
  end

  def archive
    Personalities::Archive.call(personality: @personality)
    redirect_to personalities_path, notice: t("app.flash.personality_archived")
  end

  private

  def require_completed_profile
    return if current_user.profile.present?

    redirect_to edit_profile_path, alert: t("app.flash.profile_required")
  end

  def set_personality
    @personality = current_user.personalities.find(params[:id])
  end

  def create_params
    params.require(:personality).permit(*Personalities::Create::CHARACTER_FIELDS)
  end

  def update_params
    params.require(:personality).permit(:name, :description, :character_bible)
  end
end
