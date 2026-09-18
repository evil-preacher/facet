class ProfilesController < ApplicationController
  before_action :require_authentication

  def show
    @profile = current_user.profile
    redirect_to edit_profile_path unless @profile
  end

  def edit
    @profile = current_user.profile || current_user.build_profile
  end

  def update
    @profile = current_user.profile || current_user.build_profile

    if @profile.update(profile_params)
      destination = current_user.personalities.exists? ? profile_path : new_personality_path
      redirect_to destination, notice: t("app.flash.profile_saved")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def profile_params
    params.require(:profile).permit(:first_name, :last_name, :gender, :birth_date)
  end
end
