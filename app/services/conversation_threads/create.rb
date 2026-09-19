module ConversationThreads
  class Create
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :content, :string
    attribute :client_token, :string

    attr_reader :personality, :user, :conversation_thread, :message, :assistant_message, :generation_run

    validates :content, :client_token, presence: true
    validates :content, length: { maximum: 10_000 }
    validates :client_token, format: { with: Message::CLIENT_TOKEN_FORMAT }
    validate :user_owns_personality
    validate :personality_is_active

    def self.call(personality:, user:, attributes:)
      new(personality: personality, user: user, attributes: attributes).call
    end

    def initialize(personality:, user:, attributes:)
      @personality = personality
      @user = user
      @created = false
      super(attributes.to_h.symbolize_keys.slice(:content, :client_token))
    end

    def call
      return self if invalid?
      return duplicate_result if duplicate_message

      ConversationThread.transaction do
        @conversation_thread = personality.conversation_threads.create!(
          title: Title.from(content)
        )
        @message = conversation_thread.messages.create!(
          personality_version: personality.current_version,
          position: 1,
          role: :user,
          status: :completed,
          language: Ai::LanguageDetector.call(content),
          content: content.strip,
          client_token: client_token
        )
        conversation_thread.update!(last_message_at: message.created_at)
        prepare_generation
      end
      @created = true
      enqueue_generation

      self
    rescue ActiveRecord::RecordInvalid => error
      errors.merge!(error.record.errors)
      self
    rescue ActiveRecord::RecordNotUnique
      duplicate_result
    end

    def success?
      message&.persisted? && errors.empty?
    end

    def created?
      @created
    end

    private

    def duplicate_message
      Message.joins(:conversation_thread).find_by(
        client_token: client_token,
        conversation_threads: { personality_id: personality.id }
      )
    end

    def duplicate_result
      existing = duplicate_message
      if existing
        @message = existing
        @conversation_thread = existing.conversation_thread
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

    def user_owns_personality
      return if user.present? && personality&.user_id == user.id

      errors.add(:user, :invalid)
    end

    def personality_is_active
      errors.add(:personality, :invalid) unless personality&.active?
    end
  end
end
