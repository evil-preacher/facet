module Personalities
  class Rollback
    include ActiveModel::Model

    MAX_CHANGE_NOTE_LENGTH = 500

    attr_accessor :personality, :source_version, :author, :change_note
    attr_reader :version

    validates :personality, :source_version, :author, presence: true
    validates :change_note, length: { maximum: MAX_CHANGE_NOTE_LENGTH }, allow_nil: true
    validate :source_version_belongs_to_personality
    validate :author_owns_personality

    def self.call(personality:, source_version:, author:, change_note: nil)
      new(
        personality: personality,
        source_version: source_version,
        author: author,
        change_note: change_note
      ).call
    end

    def call
      return self if invalid?

      personality.with_lock do
        @version = personality.versions.create!(
          number: personality.versions.maximum(:number).to_i + 1,
          content: source_version.content,
          source_version: source_version,
          author: author,
          change_note: normalized_change_note
        )
        personality.update!(current_version: version)
      end
      AvatarGeneration.enqueue_safely(personality: personality, personality_version: version)

      self
    rescue ActiveRecord::RecordInvalid => error
      errors.merge!(error.record.errors)
      self
    end

    def success?
      version&.persisted? && errors.empty?
    end

    private

    def normalized_change_note
      change_note.presence&.strip || "Rollback to version #{source_version.number}"
    end

    def source_version_belongs_to_personality
      return if source_version.nil? || source_version.personality_id == personality&.id

      errors.add(:source_version, :invalid)
    end

    def author_owns_personality
      return if author.nil? || author.id == personality&.user_id

      errors.add(:author, :invalid)
    end
  end
end
