Rails.application.configure do
  config.x.ai.provider = ENV.fetch("AI_PROVIDER", "mistral")
  config.x.ai.platform_prompt_enabled = ENV.fetch("AI_PLATFORM_PROMPT_ENABLED", "true").casecmp?("true")
  config.x.ai.platform_prompt_required = ENV.fetch("AI_PLATFORM_PROMPT_REQUIRED", "false").casecmp?("true")
  config.x.ai.conversation_model = if config.x.ai.provider == "openai"
    ENV.fetch("OPENAI_CONVERSATION_MODEL", "gpt-4o-2024-11-20")
  else
    ENV.fetch("MISTRAL_CONVERSATION_MODEL", "mistral-large-2512")
  end
  config.x.ai.utility_model = if config.x.ai.provider == "openai"
    ENV.fetch("OPENAI_UTILITY_MODEL", "gpt-4o-mini")
  else
    ENV.fetch("MISTRAL_UTILITY_MODEL", "mistral-small-latest")
  end
  config.x.ai.image_model = ENV.fetch("BFL_IMAGE_MODEL", "flux-2-klein-9b")
  config.x.ai.image_width = ENV.fetch("BFL_IMAGE_WIDTH", 768).to_i
  config.x.ai.image_height = ENV.fetch("BFL_IMAGE_HEIGHT", 1024).to_i
  config.x.ai.image_safety_tolerance = ENV.fetch("BFL_SAFETY_TOLERANCE", 5).to_i
  config.x.ai.debug_ui = Rails.env.development? && ENV.fetch("AI_DEBUG_UI", "true").casecmp?("true")
end
