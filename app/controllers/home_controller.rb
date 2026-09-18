class HomeController < ApplicationController
  def index
    redirect_to profile_path if authenticated?
  end
end
