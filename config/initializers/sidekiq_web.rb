require "sidekiq/web"
require Rails.root.join("lib/operations/basic_auth")

Sidekiq::Web.use Operations::BasicAuth
