module Ai
  class ProviderRegistry
    def self.gateway_for(provider)
      case provider.to_s
      when "mistral"
        Gateway.new(adapter: MistralAdapter.new)
      when "openai"
        Gateway.new(adapter: OpenaiAdapter.new)
      else
        raise ValidationError, "AI provider is not configured: #{provider}"
      end
    end
  end
end
