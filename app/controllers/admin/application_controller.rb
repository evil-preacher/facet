module Admin
  class ApplicationController < Administrate::ApplicationController
    before_action :require_admin
    before_action :set_private_headers
    around_action :switch_locale
    after_action :audit_resource_view, only: %i[index show]

    helper_method :current_admin

    private

    def current_admin
      @current_admin ||= User.find_by(id: session[:user_id])
    end

    def require_admin
      head :not_found unless current_admin&.admin? && current_admin.confirmed?
      Current.user = current_admin if current_admin&.admin?
    end

    def set_private_headers
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end

    def switch_locale(&action)
      locale = session[:locale].presence_in(I18n.available_locales.map(&:to_s)) || I18n.default_locale
      I18n.with_locale(locale, &action)
    end

    def audit_resource_view
      return unless response.successful?
      return if is_a?(OverviewController)

      AdminAuditEvent.create!(actor_user_id: current_admin.id, action: action_name,
                              target_type: resource_class.name, target_id: params[:id])
    end
  end
end
