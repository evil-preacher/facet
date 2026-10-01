module Ai
  class OpenaiAdapter < MistralAdapter
    private

    def stream_parameters(model, input, prompt_cache_key)
      request_parameters(model, input, prompt_cache_key).merge(stream_options: { include_usage: true })
    end

    def client
      @client ||= OpenAI::Client.new(
        api_key: ENV.fetch("OPENAI_API_KEY"),
        base_url: ENV.fetch("OPENAI_BASE_URL", "https://api.openai.com/v1")
      )
    end

    def serialized_role(role)
      role.to_s
    end

    def provider_name
      "OpenAI"
    end
  end
end
