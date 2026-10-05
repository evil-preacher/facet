class DataExportsController < ApplicationController
  before_action :require_authentication

  def show
    response.headers["Cache-Control"] = "private, no-store"
    send_data DataExports::Build.call(user: current_user).to_json,
              type: "application/json; charset=utf-8",
              disposition: "attachment",
              filename: "facet-data-#{Date.current.iso8601}.json"
  end
end
