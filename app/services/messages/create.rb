module Messages
  class Create
    include ActiveModel::Model
    include ActiveModel::Attributes

    MAX_USER_CONTENT_LENGTH = 10_000

    attribute :content, :string
    attribute :client_token, :string

    attr_reader :conversation_thread, :user, :message, :assistant_message, :generation_run

    validates :content, :client_token, presence: true
    validates :content, length: { maximum: MAX_USER_CONTENT_LENGTH }
    validates :client_token, format: { with: Message::CLIENT_TOKEN_FORMAT }
    validate :user_owns_thread
    validate :thread_is_active

    def self.call(conversation_thread:, user:, attributes:)
      new(conversation_thread: conversation_thread, user: user, attributes: attributes).call
    end

    def initialize(conversation_thread:, user:, attributes:)
      @conversation_thread = conversation_thread
      @user = user
      @created = false
      super(attributes.to_h.symbolize_keys.slice(:content, :client_token))
    end

    def call
      return self if invalid?

      conversation_thread.with_lock do
        existing = Message.find_by(client_token: client_token)
        return duplicate_result(existing) if existing

        @message = conversation_thread.messages.create!(
          personality_version: conversation_thread.personality.current_version,
          position: conversation_thread.messages.maximum(:position).to_i + 1,
          role: :user,
          status: :completed,
          language: Ai::LanguageDetector.call(content),
          content: content.strip,
          client_token: client_token
        )
        conversation_thread.update!(last_message_at: message.created_at)
        prepare_generation
        @created = true
      end
      enqueue_generation

      self
    rescue ActiveRecord::RecordInvalid => error
      errors.merge!(error.record.errors)
      self
    rescue ActiveRecord::RecordNotUnique
      duplicate_result(Message.find_by(client_token: client_token))
    end

    def success?
      message&.persisted? && errors.empty?
    end

    def created?
      @created
    end

    private

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
    end

    def enqueue_generation
      Ai::GenerateReplyJob.perform_later(generation_run.id) if created?
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
