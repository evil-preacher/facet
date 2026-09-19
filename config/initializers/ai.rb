Rails.application.configure do
  config.x.ai.provider = "mistral"
  config.x.ai.conversation_model = ENV.fetch("MISTRAL_CONVERSATION_MODEL", "mistral-large-2512")
  config.x.ai.utility_model = ENV.fetch("MISTRAL_UTILITY_MODEL", "mistral-small-latest")
  config.x.ai.debug_ui = Rails.env.development? && ENV.fetch("AI_DEBUG_UI", "true").casecmp?("true")
end
