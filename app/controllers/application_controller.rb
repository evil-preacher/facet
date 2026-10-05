class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :set_current_user
  around_action :switch_locale

  helper_method :current_user, :authenticated?, :unread_notification_threads_count

  def supported_locale?(locale)
    I18n.available_locales.map(&:to_s).include?(locale.to_s)
  end

  private

  def switch_locale(&action)
    locale = session[:locale].presence_in(I18n.available_locales.map(&:to_s)) || I18n.default_locale
    I18n.with_locale(locale, &action)
  end

  def set_current_user
    Current.user = User.find_by(id: session[:user_id])
  end

  def current_user
    Current.user
  end

  def authenticated?
    current_user.present?
  end

  def unread_notification_threads_count
    @unread_notification_threads_count ||= Notifications::UnreadThreads.count_for(current_user)
  end

  def after_authentication_path
    return edit_profile_path unless current_user.profile
    return new_personality_path unless current_user.personalities.exists?

    personalities_path
  end

  def require_authentication
    redirect_to root_path, alert: t("app.flash.authentication_required") unless authenticated?
  end

  def require_completed_profile
    return if current_user.profile.present?

    redirect_to edit_profile_path, alert: t("app.flash.profile_required")
  end

  def start_new_session_for(user)
    locale = session[:locale]
    reset_session
    session[:locale] = locale if supported_locale?(locale)
    session[:user_id] = user.id
    Current.user = user
  end
end
