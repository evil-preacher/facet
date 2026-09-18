class RegistrationsController < ApplicationController
  def new
  end

  def create
    email = User.normalize_email(params.dig(:registration, :email))
    user = User.find_or_initialize_by(email: email)

    if user.new_record? && !user.save
      redirect_to root_path, alert: user.errors.full_messages.to_sentence
      return
    end

    user.send_confirmation_email! unless user.confirmed?
    redirect_to root_path, notice: t("app.flash.registration_sent")
  end
end
