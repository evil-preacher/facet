require "digest"

module Operations
  class BasicAuth
    REALM = "Facet operations"

    def initialize(app)
      @app = app
    end

    def call(env)
      username = ENV["OPERATIONS_USERNAME"]
      password = ENV["OPERATIONS_PASSWORD"]
      return not_found if username.blank? || password.blank?

      Rack::Auth::Basic.new(@app, REALM) do |given_username, given_password|
        secure_compare(given_username, username) & secure_compare(given_password, password)
      end.call(env)
    end

    private

    def secure_compare(given, expected)
      ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.hexdigest(given.to_s),
        Digest::SHA256.hexdigest(expected.to_s)
      )
    end

    def not_found
      [ 404, { "content-type" => "text/plain", "content-length" => "0" }, [] ]
    end
  end
end
