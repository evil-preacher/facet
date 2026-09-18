class SessionsController < ApplicationController
  def destroy
    reset_session
    Current.user = nil
    redirect_to root_path, notice: t("app.flash.signed_out")
  end
end
