module Memories
  class Replace
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :content, :string
    attribute :kind, :string
    attribute :importance, :integer

    attr_reader :memory, :user, :replacement

    validates :content, :kind, :importance, :user, presence: true
    validates :content, length: { maximum: Memory::MAX_CONTENT_LENGTH }
    validates :kind, inclusion: { in: Memory::KINDS }
    validates :importance, numericality: { only_integer: true, in: 1..100 }
    validate :user_owns_memory
    validate :memory_is_current

    def self.call(memory:, user:, attributes:)
      new(memory: memory, user: user, attributes: attributes).call
    end

    def initialize(memory:, user:, attributes:)
      @memory = memory
      @user = user
      super(attributes.to_h.symbolize_keys.slice(:content, :kind, :importance))
    end

    def call
      return self if invalid?

      Memory.transaction do
        memory.lock!
        replaced_memory = replacement_target
        replaced_memory.lock! unless replaced_memory == memory
        memory.update!(status: :superseded)
        replaced_memory.update!(status: :superseded) unless replaced_memory == memory
        @replacement = memory.personality.memories.create!(
          kind: kind,
          content: content,
          importance: importance,
          status: :active,
          origin: :user,
          sensitivity: memory.sensitivity,
          occurred_at: memory.occurred_at,
          supersedes: replaced_memory
        )
      end
      self
    rescue ActiveRecord::RecordInvalid => error
      errors.merge!(error.record.errors)
      self
    end

    def success?
      replacement&.persisted? && errors.empty?
    end

    private

    def user_owns_memory
      return if user.nil? || memory.personality.user_id == user.id

      errors.add(:user, :invalid)
    end

    def memory_is_current
      errors.add(:memory, :invalid) unless memory.active? || memory.pending?
    end

    def replacement_target
      return memory.supersedes if memory.pending? && memory.supersedes&.active?

      memory
    end
  end
end
