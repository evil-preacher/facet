module Messages
  class Create
    include ActiveModel::Model
    include ActiveModel::Attributes

    MAX_USER_CONTENT_LENGTH = 10_000

    attribute :content, :string
    attribute :client_token, :string

    attr_reader :conversation_thread, :user, :message

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
          content: content.strip,
          client_token: client_token
        )
        conversation_thread.update!(last_message_at: message.created_at)
        @created = true
      end

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
      else
        errors.add(:client_token, :taken)
      end
      self
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
