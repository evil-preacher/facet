class LocalesController < ApplicationController
  def update
    session[:locale] = params[:locale] if supported_locale?(params[:locale])
    redirect_back fallback_location: root_path
  end
end
