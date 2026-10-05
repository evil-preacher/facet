class AccountsController < ApplicationController
  before_action :require_authentication

  def destroy
    Accounts::Destroy.call(user: current_user)
    reset_session
    Current.user = nil
    redirect_to root_path, notice: t("app.flash.account_deleted"), status: :see_other
  end
end
