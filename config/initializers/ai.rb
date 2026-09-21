Rails.application.configure do
  config.x.ai.provider = ENV.fetch("AI_PROVIDER", "mistral")
  config.x.ai.platform_prompt_required = ENV.fetch("AI_PLATFORM_PROMPT_REQUIRED", "false").casecmp?("true")
  config.x.ai.conversation_model = ENV.fetch("MISTRAL_CONVERSATION_MODEL", "mistral-large-2512")
  config.x.ai.utility_model = ENV.fetch("MISTRAL_UTILITY_MODEL", "mistral-small-latest")
  config.x.ai.image_model = ENV.fetch("BFL_IMAGE_MODEL", "flux-2-klein-9b")
  config.x.ai.image_width = ENV.fetch("BFL_IMAGE_WIDTH", 768).to_i
  config.x.ai.image_height = ENV.fetch("BFL_IMAGE_HEIGHT", 1024).to_i
  config.x.ai.image_safety_tolerance = ENV.fetch("BFL_SAFETY_TOLERANCE", 5).to_i
  config.x.ai.debug_ui = Rails.env.development? && ENV.fetch("AI_DEBUG_UI", "true").casecmp?("true")
end
