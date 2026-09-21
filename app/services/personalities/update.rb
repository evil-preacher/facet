module Personalities
  class Update
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :name, :string
    attribute :description, :string, default: ""
    attribute :character_bible, :string
    attribute :change_note, :string

    attr_reader :personality, :author

    validates :name, :character_bible, :author, presence: true
    validates :name, length: { maximum: 80 }
    validates :description, length: { maximum: 500 }
    validates :character_bible, length: { maximum: PersonalityVersion::MAX_CONTENT_LENGTH }
    validates :change_note, length: { maximum: 500 }, allow_nil: true
    validate :author_owns_personality

    def self.call(personality:, author:, attributes:)
      new(personality: personality, author: author, attributes: attributes).call
    end

    def initialize(personality:, author:, attributes:)
      @personality = personality
      @author = author
      @succeeded = false
      super(attributes.to_h.symbolize_keys.slice(:name, :description, :character_bible, :change_note))
    end

    def call
      return self if invalid?

      personality.with_lock do
        personality.update!(name: name.strip, description: description.to_s.strip)
        create_version!
      end
      @succeeded = true
      AvatarGeneration.enqueue_safely(personality: personality, personality_version: @version)

      self
    rescue ActiveRecord::RecordInvalid => error
      errors.merge!(error.record.errors)
      self
    end

    def success?
      @succeeded && errors.empty?
    end

    private

    def create_version!
      @version = personality.versions.create!(
        number: personality.versions.maximum(:number).to_i + 1,
        content: character_bible.strip,
        author: author,
        change_note: change_note.presence&.strip
      )
      personality.update!(current_version: @version)
    end

    def author_owns_personality
      return if author.nil? || author.id == personality.user_id

      errors.add(:author, :invalid)
    end
  end
end
