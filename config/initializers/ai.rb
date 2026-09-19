Rails.application.configure do
  config.x.ai.provider = "openai"
  config.x.ai.conversation_model = ENV.fetch("OPENAI_CONVERSATION_MODEL", "gpt-4o-2024-11-20")
  config.x.ai.utility_model = ENV.fetch("OPENAI_UTILITY_MODEL", "gpt-4o-mini")
  config.x.ai.debug_ui = Rails.env.development? && ENV.fetch("AI_DEBUG_UI", "true").casecmp?("true")
end
