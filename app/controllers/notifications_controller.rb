class NotificationsController < ApplicationController
  before_action :require_authentication

  def index
    @entries = Notifications::UnreadThreads.call(user: current_user)
  end
end
