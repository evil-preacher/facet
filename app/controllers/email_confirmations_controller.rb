class EmailConfirmationsController < ApplicationController
  def show
    user = User.find_signed(params[:token], purpose: :email_confirmation)

    unless user && !user.confirmed?
      render :invalid, status: :unprocessable_content
      return
    end

    user.update!(confirmed_at: Time.current) unless user.confirmed?
    start_new_session_for(user)
    redirect_to edit_profile_path, notice: t("app.flash.email_confirmed")
  end
end
