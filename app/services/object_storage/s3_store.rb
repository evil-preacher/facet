require "aws-sdk-s3"

module ObjectStorage
  class S3Store
    DEFAULT_URL_TTL = 15.minutes

    class << self
      def default
        @default ||= new
      end

      attr_writer :default
    end

    def initialize(client: nil, public_client: nil, bucket: ENV.fetch("S3_BUCKET"))
      @bucket = bucket
      @client = client || build_client(endpoint: ENV["S3_ENDPOINT"])
      public_endpoint = ENV["S3_PUBLIC_ENDPOINT"].presence || ENV["S3_ENDPOINT"]
      @public_client = public_client || build_client(endpoint: public_endpoint)
    end

    def upload(key:, body:, content_type:)
      client.put_object(
        bucket: bucket,
        key: key,
        body: body,
        content_type: content_type,
        cache_control: "private, max-age=31536000, immutable"
      )
      key
    rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError => error
      raise TransientError, "S3 upload failed: #{error.class.name}"
    end

    def download(key:)
      client.get_object(bucket: bucket, key: key).body.read.b
    rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError => error
      raise TransientError, "S3 download failed: #{error.class.name}"
    end

    def delete(key:)
      client.delete_object(bucket: bucket, key: key)
    rescue Aws::S3::Errors::NoSuchKey
      nil
    rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError => error
      raise TransientError, "S3 delete failed: #{error.class.name}"
    end

    def presigned_url(key:, expires_in: DEFAULT_URL_TTL)
      Aws::S3::Presigner.new(client: public_client).presigned_url(
        :get_object,
        bucket: bucket,
        key: key,
        expires_in: expires_in.to_i
      )
    end

    private

    attr_reader :bucket, :client, :public_client

    def build_client(endpoint:)
      options = {
        region: ENV.fetch("S3_REGION", "us-east-1"),
        force_path_style: ENV.fetch("S3_FORCE_PATH_STYLE", "false").casecmp?("true")
      }
      options[:endpoint] = endpoint if endpoint.present?
      options[:credentials] = credentials if credentials
      Aws::S3::Client.new(**options)
    end

    def credentials
      access_key = ENV["S3_ACCESS_KEY_ID"].presence
      secret_key = ENV["S3_SECRET_ACCESS_KEY"].presence
      return unless access_key && secret_key

      Aws::Credentials.new(access_key, secret_key, ENV["S3_SESSION_TOKEN"].presence)
    end
  end
end
