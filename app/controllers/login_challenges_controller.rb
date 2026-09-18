class LoginChallengesController < ApplicationController
  IP_REQUEST_LIMIT = 10

  def create
    email = User.normalize_email(params.dig(:login, :email))
    user = User.find_by(email: email, confirmed_at: ..Time.current)
    challenge = issue_challenge_for(user)

    redirect_to verify_login_path(token: challenge&.token || SecureRandom.urlsafe_base64(24)),
                notice: t("app.flash.login_code_sent")
  end

  def new
    @token = params[:token].to_s
  end

  def verify
    challenge = LoginChallenge.find_by(token: params.dig(:login, :token))

    if challenge&.verify(params.dig(:login, :code))
      start_new_session_for(challenge.user)
      redirect_to after_authentication_path, notice: t("app.flash.signed_in")
    else
      @token = params.dig(:login, :token).to_s
      flash.now[:alert] = t("app.flash.invalid_code")
      render :new, status: :unprocessable_content
    end
  end

  private

  def issue_challenge_for(user)
    return unless user

    recent = user.login_challenges.order(created_at: :desc).first
    return recent if recent&.created_at&.after?(LoginChallenge::RESEND_INTERVAL.ago) && recent.usable?
    return if ip_request_limit_reached?

    challenge, code = LoginChallenge.issue_for!(user: user, requested_ip: request.remote_ip)
    UserMailer.with(user: user, code: code).login_code.deliver_now
    challenge
  end

  def ip_request_limit_reached?
    LoginChallenge.where(requested_ip: request.remote_ip)
                  .where(created_at: 1.minute.ago..)
                  .count >= IP_REQUEST_LIMIT
  end
end
