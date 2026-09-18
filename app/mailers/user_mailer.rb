class UserMailer < ApplicationMailer
  def confirmation_email
    @user = params[:user]
    @confirmation_url = email_confirmation_url(token: @user.confirmation_token)
    mail(to: @user.email, subject: t("app.mailer.confirmation.subject"))
  end

  def login_code
    @user = params[:user]
    @code = params[:code]
    mail(to: @user.email, subject: t("app.mailer.login.subject"))
  end
end
