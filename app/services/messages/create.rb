module Messages
  class Create
    include ActiveModel::Model
    include ActiveModel::Attributes

    MAX_USER_CONTENT_LENGTH = 10_000

    attribute :content, :string
    attribute :client_token, :string
    attr_reader :image

    attr_reader :conversation_thread, :user, :message, :assistant_message, :generation_run

    validates :client_token, presence: true
    validates :content, length: { maximum: MAX_USER_CONTENT_LENGTH }
    validates :client_token, format: { with: Message::CLIENT_TOKEN_FORMAT }
    validate :content_or_image_present
    validate :image_is_valid
    validate :user_owns_thread
    validate :thread_is_active

    def self.call(conversation_thread:, user:, attributes:, storage: ObjectStorage::S3Store.default)
      new(conversation_thread: conversation_thread, user: user, attributes: attributes, storage: storage).call
    end

    def initialize(conversation_thread:, user:, attributes:, storage:)
      @conversation_thread = conversation_thread
      @user = user
      @storage = storage
      @created = false
      values = attributes.to_h.symbolize_keys
      @image = values[:image]
      super(values.slice(:content, :client_token))
    end

    def call
      return self if invalid?

      conversation_thread.with_lock do
        existing = Message.find_by(client_token: client_token)
        return duplicate_result(existing) if existing

        upload_attachment if prepared_image
        @message = conversation_thread.messages.build(
          personality_version: conversation_thread.personality.current_version,
          position: conversation_thread.messages.maximum(:position).to_i + 1,
          role: :user,
          status: :completed,
          language: Ai::LanguageDetector.call(content.to_s),
          content: content.to_s.strip,
          client_token: client_token
        )
        build_attachment
        @message.save!
        conversation_thread.update!(last_message_at: message.created_at)
        prepare_generation
        @created = true
      end
      enqueue_generation

      self
    rescue ActiveRecord::RecordInvalid => error
      cleanup_attachment
      errors.merge!(error.record.errors)
      self
    rescue ActiveRecord::RecordNotUnique
      cleanup_attachment
      duplicate_result(Message.find_by(client_token: client_token))
    rescue ObjectStorage::Error
      cleanup_attachment
      errors.add(:image, :upload_failed)
      self
    end

    def success?
      message&.persisted? && errors.empty?
    end

    def created?
      @created
    end

    private

    attr_reader :storage

    def prepared_image
      return @prepared_image if defined?(@prepared_image)

      @prepared_image = image.present? ? ImageUpload.call(image) : nil
    rescue Ai::ValidationError
      @image_invalid = true
      @prepared_image = nil
    end

    def upload_attachment
      @attachment_key = "messages/attachments/#{SecureRandom.uuid}.#{prepared_image.extension}"
      storage.upload(
        key: @attachment_key,
        body: prepared_image.bytes,
        content_type: prepared_image.content_type
      )
    end

    def build_attachment
      return unless prepared_image

      message.build_attachment(
        object_key: @attachment_key,
        content_type: prepared_image.content_type,
        byte_size: prepared_image.bytes.bytesize,
        original_filename: prepared_image.original_filename
      )
    end

    def cleanup_attachment
      storage.delete(key: @attachment_key) if @attachment_key
    rescue ObjectStorage::Error
      nil
    end

    def duplicate_result(existing)
      if existing&.conversation_thread_id == conversation_thread.id
        @message = existing
        @generation_run = existing.generation_runs_as_user.find_by(retry_of_id: nil)
        @assistant_message = generation_run&.assistant_message
      else
        errors.add(:client_token, :taken)
      end
      self
    end

    def prepare_generation
      prepared = GenerationRuns::Prepare.call(
        conversation_thread: conversation_thread,
        user_message: message
      )
      @generation_run = prepared.generation_run
      @assistant_message = prepared.assistant_message
      @outbox_event = prepared.outbox_event
    end

    def enqueue_generation
      Outbox::Dispatcher.call(limit: 1, event_ids: [ @outbox_event.id ]) if created?
    end

    def content_or_image_present
      return if content.to_s.strip.present? || image.present?

      errors.add(:content, :blank)
    end

    def image_is_valid
      prepared_image
      errors.add(:image, :invalid_image) if @image_invalid
    end

    def user_owns_thread
      return if user.present? && conversation_thread&.personality&.user_id == user.id

      errors.add(:user, :invalid)
    end

    def thread_is_active
      active = conversation_thread&.active? && conversation_thread.personality.active?
      errors.add(:conversation_thread, :invalid) unless active
    end
  end
end
