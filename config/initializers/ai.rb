Rails.application.configure do
  config.x.ai.provider = "openai"
  config.x.ai.conversation_model = ENV.fetch("OPENAI_CONVERSATION_MODEL", "gpt-4o")
  config.x.ai.utility_model = ENV.fetch("OPENAI_UTILITY_MODEL", "gpt-4o-mini")
end
