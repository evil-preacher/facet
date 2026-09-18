module Personalities
  class Update
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :name, :string
    attribute :description, :string, default: ""
    attribute :character_bible, :string

    attr_reader :personality

    validates :name, :character_bible, presence: true
    validates :name, length: { maximum: 80 }
    validates :description, length: { maximum: 500 }
    validates :character_bible, length: { maximum: PersonalityVersion::MAX_CONTENT_LENGTH }

    def self.call(personality:, attributes:)
      new(personality: personality, attributes: attributes).call
    end

    def initialize(personality:, attributes:)
      @personality = personality
      @succeeded = false
      super(attributes.to_h.symbolize_keys.slice(:name, :description, :character_bible))
    end

    def call
      return self if invalid?

      personality.with_lock do
        personality.update!(name: name.strip, description: description.to_s.strip)
        create_version_if_changed!
      end
      @succeeded = true

      self
    rescue ActiveRecord::RecordInvalid => error
      errors.merge!(error.record.errors)
      self
    end

    def success?
      @succeeded && errors.empty?
    end

    private

    def create_version_if_changed!
      content = character_bible.strip
      return if personality.current_version&.content == content

      version = personality.versions.create!(
        number: personality.versions.maximum(:number).to_i + 1,
        content: content
      )
      personality.update!(current_version: version)
    end
  end
end
