module Ai
  class OpenAiAdapter
    def initialize(client: nil)
      @client = client
    end

    def response(model:, input:, prompt_cache_key: nil)
      normalize(client.responses.create(**request_parameters(model, input, prompt_cache_key)))
    rescue OpenAI::Errors::APITimeoutError => error
      raise TimeoutError.new(error.message, request_id: request_id_from(error)), cause: error
    rescue OpenAI::Errors::RateLimitError => error
      raise RateLimitError.new(error.message, request_id: request_id_from(error)), cause: error
    rescue OpenAI::Errors::APIError => error
      raise ProviderError.new(error.message, request_id: request_id_from(error)), cause: error
    end

    def stream_response(model:, input:, prompt_cache_key: nil)
      stream = client.responses.stream(**request_parameters(model, input, prompt_cache_key))
      completed_response = nil
      streamed_text = +""

      stream.each do |event|
        case event.type.to_s
        when "response.output_text.delta"
          streamed_text << event.delta
          yield event.delta if block_given?
        when "response.completed"
          completed_response = event.response
        when "response.failed", "response.incomplete"
          raise ProviderError, "Provider did not complete the response"
        end
      end

      normalize(
        completed_response,
        fallback_text: streamed_text,
        fallback_request_id: stream_request_id(stream)
      )
    rescue OpenAI::Errors::APITimeoutError => error
      raise TimeoutError.new(error.message, request_id: request_id_from(error)), cause: error
    rescue OpenAI::Errors::RateLimitError => error
      raise RateLimitError.new(error.message, request_id: request_id_from(error)), cause: error
    rescue OpenAI::Errors::APIError => error
      raise ProviderError.new(error.message, request_id: request_id_from(error)), cause: error
    end

    private

    def request_parameters(model, input, prompt_cache_key)
      {
        model: model,
        input: serialize_input(input),
        store: false
      }.tap do |parameters|
        parameters[:prompt_cache_key] = prompt_cache_key if prompt_cache_key.present?
      end
    end

    def serialize_input(input)
      return input unless input.is_a?(Array)

      input.map do |item|
        if item.respond_to?(:role) && item.respond_to?(:content)
          { role: item.role, content: item.content }
        else
          item
        end
      end
    end

    def client
      @client ||= OpenAI::Client.new(api_key: ENV.fetch("OPENAI_API_KEY"))
    end

    def normalize(raw, fallback_text: nil, fallback_request_id: nil)
      raise MalformedResponseError, "Provider omitted the completed response" unless raw

      usage = raw.usage
      Response.new(
        text: raw.output_text.presence || fallback_text,
        request_id: fallback_request_id.presence || response_request_id(raw),
        usage: Usage.new(
          input_tokens: usage.input_tokens,
          cached_input_tokens: usage.input_tokens_details&.cached_tokens || 0,
          output_tokens: usage.output_tokens
        )
      )
    rescue NoMethodError, TypeError, ArgumentError => error
      raise MalformedResponseError.new("Provider returned an invalid response"), cause: error
    end

    def request_id_from(error)
      error.request_id if error.respond_to?(:request_id)
    end

    def response_request_id(response)
      http_request_id = response._request_id if response.respond_to?(:_request_id)
      http_request_id.presence || response.id.presence
    end

    def stream_request_id(stream)
      stream._request_id if stream.respond_to?(:_request_id)
    end
  end
end
