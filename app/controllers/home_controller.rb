class HomeController < ApplicationController
  def index
    redirect_to after_authentication_path if authenticated?
  end
end
