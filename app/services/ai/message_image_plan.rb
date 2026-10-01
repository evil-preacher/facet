require "json"

module Ai
  class MessageImagePlan
    Result = Data.define(:send_photo, :scene_description)

    SYSTEM_PROMPT = <<~PROMPT.strip.freeze
      [Prompt text removed from public history]
    PROMPT

    ERROR_CLASSES = {
      "timeout" => TimeoutError,
      "rate_limit" => RateLimitError,
      "validation_error" => ValidationError,
      "malformed_response" => MalformedResponseError
    }.freeze

    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(message_image:, gateway: nil, now: Time.current)
      @message_image = message_image
      @message = message_image.message
      @thread = @message.conversation_thread
      @personality = @thread.personality
      @provider = @message.generation_run_as_assistant&.ai_provider || Rails.configuration.x.ai.provider
      @gateway = gateway || ProviderRegistry.gateway_for(@provider)
      @now = now
    end

    def call
      request = Request.call(
        user: personality.user,
        personality: personality,
        purpose: :photo_planning,
        model: personality.utility_model,
        input: input,
        gateway: gateway,
        provider: @provider,
        now: now
      )
      raise_request_error!(request.error_code) unless request.success?

      parse(request.response.text)
    end

    private

    attr_reader :message_image, :message, :thread, :personality, :gateway, :now

    def input
      [
        { role: "system", content: SYSTEM_PROMPT },
        {
          role: "user",
          content: <<~CONTENT.strip
      [Prompt text removed from public history]
          CONTENT
        }
      ]
    end

    def user_message
      message.generation_run_as_assistant&.user_message ||
        thread.messages.user.where("position < ?", message.position).order(position: :desc).first
    end

    def parse(text)
      payload = JSON.parse(json_object(text))
      send_photo = payload.fetch("send_photo")
      scene = payload.fetch("scene_description").to_s.strip
      valid = [ true, false ].include?(send_photo) &&
        (!send_photo || scene.present?) &&
        (send_photo || scene.empty?) &&
        scene.length <= 4_000
      raise MalformedResponseError, "Photo plan has an invalid schema" unless valid

      Result.new(send_photo: send_photo, scene_description: scene)
    rescue JSON::ParserError, KeyError, TypeError => error
      raise MalformedResponseError.new("Photo planner returned invalid JSON"), cause: error
    end

    def json_object(text)
      value = text.to_s.strip
      value = value.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
      value
    end

    def raise_request_error!(code)
      error_class = ERROR_CLASSES.fetch(code, ProviderError)
      raise error_class, "Photo planning failed: #{code}"
    end
  end
end
