module Personalities
  class Create
    include ActiveModel::Model
    include ActiveModel::Attributes

    REQUIRED_FIELDS = %i[name base_character communication_style].freeze
    OPTIONAL_FIELDS = %i[
      description
      likes
      dislikes
      relationship_context
      allowed_behaviors
      forbidden_behaviors
    ].freeze
    CHARACTER_FIELDS = (REQUIRED_FIELDS + OPTIONAL_FIELDS).freeze

    attribute :name, :string
    attribute :description, :string, default: ""
    attribute :base_character, :string
    attribute :communication_style, :string
    attribute :likes, :string, default: ""
    attribute :dislikes, :string, default: ""
    attribute :relationship_context, :string, default: ""
    attribute :allowed_behaviors, :string, default: ""
    attribute :forbidden_behaviors, :string, default: ""

    attr_reader :personality, :user

    validates :name, :base_character, :communication_style, presence: true
    validates :name, length: { maximum: 80 }
    validates :description, length: { maximum: 500 }
    validates(*CHARACTER_FIELDS.excluding(:name, :description), length: { maximum: 4_000 })

    def self.call(user:, attributes:)
      new(user: user, attributes: attributes).call
    end

    def initialize(user:, attributes:)
      @user = user
      super(attributes.to_h.symbolize_keys.slice(*CHARACTER_FIELDS))
    end

    def call
      return self if invalid?

      Personality.transaction do
        @personality = user.personalities.create!(
          name: name.strip,
          description: description.to_s.strip,
          status: :draft,
          conversation_model: Rails.configuration.x.ai.conversation_model,
          utility_model: Rails.configuration.x.ai.utility_model
        )
        version = personality.versions.create!(
          number: 1,
          content: CharacterBible.compile(character_attributes),
          author: user
        )
        personality.update!(current_version: version, status: :active)
      end

      self
    rescue ActiveRecord::RecordInvalid => error
      errors.merge!(error.record.errors)
      self
    end

    def success?
      personality&.persisted? && errors.empty?
    end

    private

    def character_attributes
      CHARACTER_FIELDS.index_with { |field| public_send(field) }
    end
  end
end
