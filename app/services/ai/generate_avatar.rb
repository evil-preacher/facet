module Ai
  class GenerateAvatar
    Result = Data.define(:status, :error_code)

    TERMINAL_ERRORS = {
      MissingAvatarContextError => [ "missing_avatar_context", "Character bible has no Identity or Base character section" ],
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

    def self.mark_terminal!(personality_id:, personality_version_id:, error_code:)
      personality = Personality.find_by(id: personality_id)
      return unless personality

      personality.with_lock do
        next unless personality.avatar_source_version_id == personality_version_id
        next if personality.avatar_ready?

        personality.update!(
          avatar_status: :failed,
          avatar_started_at: nil,
          avatar_error_code: error_code,
          avatar_error_message: "Avatar generation failed after retries"
        )
      end
    end

    def initialize(personality:, personality_version:, generator: BflImageAdapter.new,
                   storage: ObjectStorage::S3Store.default, now: Time.current)
      @personality = personality
      @personality_version = personality_version
      @generator = generator
      @storage = storage
      @now = now
    end

    def call
      return Result.new(status: :skipped, error_code: nil) unless claim!

      prompt = AvatarPrompt.call(
        personality: personality,
        personality_version: personality_version
      )
      image = generator.generate(
        model: Rails.configuration.x.ai.image_model,
        prompt: prompt
      )
      key = object_key(image.content_type)
      storage.upload(key: key, body: image.bytes, content_type: image.content_type)

      unless complete!(key: key, image: image)
        safely_delete(key)
        return Result.new(status: :skipped, error_code: nil)
      end

      Result.new(status: :completed, error_code: nil)
    rescue *TERMINAL_ERRORS.keys => error
      code, message = TERMINAL_ERRORS.fetch(error.class)
      fail_current!(code: code, message: message)
      Result.new(status: :failed, error_code: code)
    rescue *RETRYABLE_ERRORS.keys => error
      retryable_failure!(RETRYABLE_ERRORS.fetch(error.class))
    rescue StandardError => error
      Rails.logger.error(
        "Unexpected avatar generation failure personality_id=#{personality.id} " \
        "version_id=#{personality_version.id} error=#{error.class.name}"
      )
      retryable_failure!("unexpected_error")
    end

    private

    attr_reader :personality, :personality_version, :generator, :storage, :now

    def claim!
      personality.with_lock do
        return false unless personality.avatar_source_version_id == personality_version.id
        return false if personality.avatar_ready? || personality.avatar_object_key.present?
        return false unless personality.avatar_pending? || personality.avatar_failed?

        personality.update!(
          avatar_status: :generating,
          avatar_started_at: now,
          avatar_attempts_count: personality.avatar_attempts_count + 1,
          avatar_error_code: nil,
          avatar_error_message: nil
        )
      end
      true
    end

    def complete!(key:, image:)
      personality.with_lock do
        return false unless personality.avatar_source_version_id == personality_version.id
        return false if personality.avatar_ready?

        personality.update!(
          avatar_status: :ready,
          avatar_object_key: key,
          avatar_content_type: image.content_type,
          avatar_byte_size: image.bytes.bytesize,
          avatar_started_at: nil,
          avatar_generated_at: now,
          avatar_error_code: nil,
          avatar_error_message: nil
        )
      end
      true
    end

    def retryable_failure!(code)
      update_current!(
        avatar_status: :pending,
        avatar_started_at: nil,
        avatar_error_code: code,
        avatar_error_message: "Avatar generation will be retried"
      )
      raise RetryableAvatarError.new(
        personality_id: personality.id,
        personality_version_id: personality_version.id,
        error_code: code
      )
    end

    def fail_current!(code:, message:)
      update_current!(
        avatar_status: :failed,
        avatar_started_at: nil,
        avatar_error_code: code,
        avatar_error_message: message
      )
    end

    def update_current!(attributes)
      personality.with_lock do
        next unless personality.avatar_source_version_id == personality_version.id
        next if personality.avatar_ready?

        personality.update!(attributes)
      end
    end

    def object_key(content_type)
      extension = case content_type
      when "image/png"
        "png"
      when "image/jpeg"
        "jpg"
      else
        raise MalformedResponseError, "Unsupported avatar content type"
      end

      "personalities/#{personality.id}/avatars/version-#{personality_version.id}.#{extension}"
    end

    def safely_delete(key)
      storage.delete(key: key)
    rescue ObjectStorage::Error => error
      Rails.logger.warn(
        "Could not delete stale avatar object key=#{key} error=#{error.class.name}"
      )
    end
  end
end
