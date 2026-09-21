module Ai
  class GenerateMessageImage
    Result = Data.define(:status, :error_code)

    TERMINAL_ERRORS = {
      MalformedResponseError => [ "malformed_response", "Image provider returned an invalid image" ],
      ValidationError => [ "validation_error", "Image provider rejected the request" ]
    }.freeze

    RETRYABLE_ERRORS = {
      TimeoutError => "timeout",
      RateLimitError => "rate_limit",
      ProviderError => "provider_error",
      ObjectStorage::TransientError => "storage_error"
    }.freeze

    def self.call(**arguments)
      new(**arguments).call
    end

    def self.mark_terminal!(message_image_id:, error_code:)
      image = MessageImage.find_by(id: message_image_id)
      return unless image

      image.with_lock do
        next if image.status_ready? || image.status_declined?

        image.update!(
          status: :failed,
          started_at: nil,
          error_code: error_code,
          error_message: "Photo generation failed after retries"
        )
      end
    end

    def initialize(message_image:, planner: MessageImagePlan, generator: BflImageAdapter.new,
                   storage: ObjectStorage::S3Store.default, now: Time.current)
      @message_image = message_image
      @planner = planner
      @generator = generator
      @storage = storage
      @now = now
    end

    def call
      return Result.new(status: :skipped, error_code: nil) unless claim!

      unless prepare_scene!
        decline!
        return Result.new(status: :declined, error_code: nil)
      end

      reference = storage.download(key: message_image.source_avatar_object_key)
      image = generator.generate(
        model: Rails.configuration.x.ai.image_model,
        prompt: MessageImagePrompt.call(message_image: message_image),
        reference_images: [ reference ]
      )
      key = object_key(image.content_type)
      storage.upload(key: key, body: image.bytes, content_type: image.content_type)
      complete!(key: key, image: image)

      Result.new(status: :completed, error_code: nil)
    rescue *TERMINAL_ERRORS.keys => error
      code, message = TERMINAL_ERRORS.fetch(error.class)
      fail_current!(code: code, message: message)
      Result.new(status: :failed, error_code: code)
    rescue *RETRYABLE_ERRORS.keys => error
      retryable_failure!(RETRYABLE_ERRORS.fetch(error.class))
    rescue StandardError => error
      Rails.logger.error(
        "Unexpected message image failure message_image_id=#{message_image.id} error=#{error.class.name}"
      )
      retryable_failure!("unexpected_error")
    end

    private

    attr_reader :message_image, :planner, :generator, :storage, :now

    def prepare_scene!
      return true if message_image.scene_description.present?

      plan = planner.call(message_image: message_image)
      return false unless plan.send_photo

      message_image.update!(scene_description: plan.scene_description)
      true
    end

    def decline!
      message_image.update!(
        status: :declined,
        started_at: nil,
        error_code: nil,
        error_message: nil
      )
    end

    def claim!
      message_image.with_lock do
        return false if message_image.status_ready? || message_image.status_declined? ||
                        message_image.object_key.present?
        return false unless message_image.status_pending? || message_image.status_failed?
        return false unless message_image.message.completed?

        message_image.update!(
          status: :generating,
          started_at: now,
          attempts_count: message_image.attempts_count + 1,
          error_code: nil,
          error_message: nil
        )
      end
      true
    end

    def complete!(key:, image:)
      message_image.with_lock do
        message_image.update!(
          status: :ready,
          object_key: key,
          content_type: image.content_type,
          byte_size: image.bytes.bytesize,
          started_at: nil,
          generated_at: now,
          provider_request_id: image.request_id,
          model: image.model,
          error_code: nil,
          error_message: nil
        )
      end
    end

    def retryable_failure!(code)
      fail_current!(code: code, message: "Photo generation will be retried", status: :pending)
      raise RetryableMessageImageError.new(message_image_id: message_image.id, error_code: code)
    end

    def fail_current!(code:, message:, status: :failed)
      message_image.with_lock do
        next if message_image.status_ready?

        message_image.update!(
          status: status,
          started_at: nil,
          error_code: code,
          error_message: message
        )
      end
    end

    def object_key(content_type)
      extension = content_type == "image/png" ? "png" : "jpg"
      "messages/#{message_image.message_id}/images/#{message_image.id}.#{extension}"
    end
  end
end
