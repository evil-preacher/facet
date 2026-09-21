require "base64"
require "json"
require "net/http"
require "uri"

module Ai
  class BflImageAdapter
    API_BASE_URL = "https://api.bfl.ai/v1"
    MAX_IMAGE_BYTES = 15.megabytes
    MAX_REFERENCE_IMAGES = 4
    POLL_INTERVAL = 0.5
    POLL_TIMEOUT = 120
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
    JPEG_SIGNATURE = "\xFF\xD8\xFF".b

    HttpResponse = Data.define(:status, :headers, :body)

    class HttpClient
      def initialize(api_key:, base_url:)
        @api_key = api_key
        @base_url = base_url.to_s.chomp("/")
      end

      def post_json(path, payload)
        request(:post, URI.parse("#{base_url}#{path}"), authenticated: true,
                      body: JSON.generate(payload), content_type: "application/json")
      end

      def get_json(url)
        request(:get, URI.parse(url), authenticated: true)
      end

      def download(url)
        request(:get, URI.parse(url), authenticated: false)
      end

      private

      attr_reader :api_key, :base_url

      def request(method, uri, authenticated:, body: nil, content_type: nil)
        request_class = method == :post ? Net::HTTP::Post : Net::HTTP::Get
        http_request = request_class.new(uri)
        http_request["x-key"] = api_key if authenticated
        http_request["Accept"] = "application/json"
        http_request["Content-Type"] = content_type if content_type
        http_request.body = body if body

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 120
        http.write_timeout = 30

        response = http.request(http_request)
        HttpResponse.new(
          status: response.code.to_i,
          headers: response.each_header.to_h,
          body: response.body.to_s
        )
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Timeout::Error => error
        raise TimeoutError, "BFL image request timed out: #{error.class.name}"
      rescue SocketError, EOFError, Errno::ECONNRESET, Errno::ECONNREFUSED => error
        raise ProviderError, "BFL image request failed: #{error.class.name}"
      end
    end

    def initialize(client: nil, sleeper: ->(seconds) { sleep(seconds) }, clock: Process.method(:clock_gettime))
      @client = client || HttpClient.new(
        api_key: ENV.fetch("BFL_API_KEY"),
        base_url: ENV.fetch("BFL_BASE_URL", API_BASE_URL)
      )
      @sleeper = sleeper
      @clock = clock
    end

    def generate(model:, prompt:, reference_images: [])
      request_payload = build_payload(prompt: prompt, reference_images: reference_images)
      log_debug("BFL image request payload", debug_payload(request_payload))
      submission = client.post_json("/#{model}", request_payload)
      ensure_success!(submission)
      submission_payload = parse_json(submission)
      request_id = submission_payload.fetch("id")
      polling_url = submission_payload.fetch("polling_url")
      result_payload = poll_until_ready(polling_url)
      image_url = result_payload.dig("result", "sample")
      raise MalformedResponseError, "BFL response omitted the generated image URL" if image_url.blank?

      image_response = client.download(image_url)
      ensure_success!(image_response)
      bytes = image_response.body.b
      content_type = detect_content_type(bytes)
      log_debug(
        "BFL image file response",
        request_id: request_id,
        content_type: content_type,
        byte_size: bytes.bytesize
      )

      AvatarImage.new(
        bytes: bytes,
        content_type: content_type,
        request_id: request_id,
        model: model
      )
    rescue JSON::ParserError, KeyError, TypeError => error
      raise MalformedResponseError.new("BFL returned an invalid image response"), cause: error
    end

    private

    attr_reader :client, :sleeper, :clock

    def build_payload(prompt:, reference_images:)
      references = Array(reference_images)
      if references.size > MAX_REFERENCE_IMAGES
        raise ValidationError, "BFL supports at most #{MAX_REFERENCE_IMAGES} reference images"
      end

      payload = {
        prompt: prompt,
        width: Rails.configuration.x.ai.image_width,
        height: Rails.configuration.x.ai.image_height,
        safety_tolerance: Rails.configuration.x.ai.image_safety_tolerance,
        output_format: "jpeg"
      }
      references.each_with_index do |bytes, index|
        key = index.zero? ? :input_image : :"input_image_#{index + 1}"
        payload[key] = Base64.strict_encode64(bytes)
      end
      payload
    end

    def poll_until_ready(url)
      deadline = monotonic_now + POLL_TIMEOUT

      loop do
        raise TimeoutError, "BFL image generation timed out" if monotonic_now >= deadline

        sleeper.call(POLL_INTERVAL)
        response = client.get_json(url)
        ensure_success!(response)
        payload = parse_json(response)
        log_debug("BFL image status response", debug_status_payload(payload))

        case payload.fetch("status")
        when "Ready"
          return payload
        when "Error", "Failed"
          raise ProviderError, "BFL image generation failed"
        end
      end
    end

    def parse_json(response)
      JSON.parse(response.body)
    end

    def detect_content_type(bytes)
      if bytes.bytesize > MAX_IMAGE_BYTES
        raise MalformedResponseError, "Generated image exceeds the size limit"
      end
      return "image/png" if bytes.start_with?(PNG_SIGNATURE)
      return "image/jpeg" if bytes.start_with?(JPEG_SIGNATURE)

      raise MalformedResponseError, "Generated file is not a supported image"
    end

    def ensure_success!(response)
      return if response.status.between?(200, 299)

      log_debug(
        "BFL image HTTP error",
        status: response.status,
        body: response.body.to_s.truncate(2_000)
      )

      if response.status == 429
        raise RateLimitError, "BFL image rate limit exceeded"
      elsif response.status >= 500 || response.status == 408
        raise ProviderError, "BFL image API returned HTTP #{response.status}"
      else
        raise ValidationError, "BFL image API rejected the request with HTTP #{response.status}"
      end
    end

    def monotonic_now
      clock.call(Process::CLOCK_MONOTONIC)
    end

    def debug_status_payload(payload)
      payload.deep_dup.tap do |copy|
        copy["result"]["sample"] = "[signed URL redacted]" if copy["result"].is_a?(Hash)
      end
    end

    def debug_payload(payload)
      payload.to_h do |key, value|
        redacted = key.to_s.start_with?("input_image") ? "[#{value.bytesize} bytes]" : value
        [ key, redacted ]
      end
    end

    def log_debug(message, payload)
      return unless Rails.env.development? && ENV["AI_DEBUG_PAYLOADS"].to_s.casecmp?("true")

      Rails.logger.info("#{message}: #{payload.inspect}")
    end
  end
end
