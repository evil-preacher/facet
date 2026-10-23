module Ai
  class PromptCatalog
    MissingPromptError = Class.new(StandardError)
    VARIABLES = {
      "application_rules" => [],
      "memory_extraction" => [],
      "relationship_update" => [],
      "relationship_update_language" => %w[language_name],
      "relationship_consolidate" => [],
      "relationship_consolidate_language" => %w[language_name],
      "relationship_scope_check" => [],
      "thread_summary" => [],
      "initiative_decision" => [],
      "initiative_message" => [],
      "initiative_character_bible" => %w[character_bible],
      "message_image_plan" => [],
      "avatar_image" => %w[character_name character_context],
      "message_image" => %w[character_name photo_specification],
      "character_bible" => %w[name description base_character communication_style likes dislikes relationship_context allowed_behaviors forbidden_behaviors],
      "image_without_caption" => []
    }.freeze
    KEYS = VARIABLES.keys.freeze

    def self.active(key)
      validate_key!(key)
      AiPromptRevision.active.find_by(key: key)
    end

    def self.content(key)
      active(key)&.content || raise(MissingPromptError, "No active prompt revision for #{key}; import or publish one")
    end

    def self.render(key, variables = {})
      expected = VARIABLES.fetch(key.to_s)
      values = variables.stringify_keys
      template = content(key)
      missing = placeholders(template) - values.keys
      raise ArgumentError, "Missing prompt variables: #{missing.join(', ')}" if missing.any?
      raise ArgumentError, "Unexpected prompt variables" if (values.keys - expected).any?

      template.gsub(/\{\{([a-z_]+)\}\}/) { values.fetch(Regexp.last_match(1)).to_s }
    end

    def self.placeholders(content)
      content.to_s.scan(/\{\{([a-z_]+)\}\}/).flatten.uniq
    end

    def self.publish(key:, content:, actor: nil)
      validate_key!(key)
      value = content.to_s.strip
      AiPromptRevision.transaction do
        AiPromptRevision.connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{AiPromptRevision.connection.quote("ai_prompt:#{key}")}))")
        current = active(key)
        return current if current&.content == value

        current&.update!(status: :retired)
        AiPromptRevision.create!(key: key, revision: AiPromptRevision.where(key: key).maximum(:revision).to_i + 1,
                                 content: value, status: :active, published_by: actor)
      end
    end

    def self.validate_key!(key)
      raise ArgumentError, "Unknown prompt key" unless KEYS.include?(key.to_s)
    end
    private_class_method :validate_key!
  end
end
