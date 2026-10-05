module Operations
  class BaseController < ApplicationController
    skip_before_action :set_current_user
    skip_around_action :switch_locale
    before_action :authenticate_operator!

    private

    def authenticate_operator!
      username = ENV["OPERATIONS_USERNAME"]
      password = ENV["OPERATIONS_PASSWORD"]
      return head :not_found if username.blank? || password.blank?

      authenticate_or_request_with_http_basic("Facet operations") do |given_username, given_password|
        ActiveSupport::SecurityUtils.secure_compare(given_username, username) &
          ActiveSupport::SecurityUtils.secure_compare(given_password, password)
      end
    end
  end
end
