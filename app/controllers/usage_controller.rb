class UsageController < ApplicationController
  before_action :require_authentication

  def show
    @report = Ai::UsageReport.call(user: current_user)
    @personalities = current_user.personalities.where(id: @report.by_personality.keys.compact).index_by(&:id)
  end

  def update
    value = params.require(:monthly_limit_usd).to_s
    raise ArgumentError unless value.match?(/\A(?:0|[1-9]\d{0,4})(?:\.\d{1,6})?\z/)

    dollars = BigDecimal(value)
    micros = (dollars * 1_000_000).to_i
    raise ArgumentError if dollars.negative? || dollars > 10_000 || dollars * 1_000_000 != micros

    current_user.update!(monthly_ai_limit_microusd: micros)
    redirect_to usage_path, notice: t("app.flash.usage_limit_updated")
  rescue ArgumentError, ActionController::ParameterMissing
    redirect_to usage_path, alert: t("app.usage.invalid_limit")
  end
end
