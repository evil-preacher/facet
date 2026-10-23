module TestPromptRevisions
  CHARACTER_BIBLE = <<~TEMPLATE.freeze
    # Identity

    Name: {{name}}
    {{description}}

    # Base character

    {{base_character}}

    # Communication style

    {{communication_style}}

    ## Likes

    {{likes}}

    ## Dislikes

    {{dislikes}}

    # Relationship context

    {{relationship_context}}

    # Allowed behaviors

    {{allowed_behaviors}}

    # Boundaries

    {{forbidden_behaviors}}
  TEMPLATE

  CONTENT = {
    "character_bible" => CHARACTER_BIBLE,
    "avatar_image" => "Test portrait of {{character_name}}. <character_context>{{character_context}}</character_context>",
    "message_image" => "Character name: {{character_name}}. Scene: {{photo_specification}}",
    "relationship_update_language" => "Write the entire summary in {{language_name}}"
  }.freeze

  def self.seed!
    return if AiPromptRevision.active.count == Ai::PromptCatalog::KEYS.length

    Ai::PromptCatalog::VARIABLES.each do |key, variables|
      next if AiPromptRevision.active.exists?(key: key)

      content = CONTENT[key] || ([ "Test #{key.humanize}" ] + variables.map { |name| "{{#{name}}}" }).join("\n")
      AiPromptRevision.create!(key: key, revision: 1, content: content, status: :active)
    end
  end
end
