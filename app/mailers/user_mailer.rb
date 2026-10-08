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

  def initiative_email
    @personality = params[:personality]
    @message = params[:message]
    @thread_url = personality_conversation_thread_url(@personality, @message.conversation_thread)
    headers["Message-ID"] = params[:email_message_id]
    I18n.with_locale(params[:locale]) do
      mail(to: @personality.user.email,
           subject: t("app.mailer.initiative.subject", name: @personality.name))
    end
  end
end
