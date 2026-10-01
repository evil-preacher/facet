module Ai
  class MistralAdapter
    API_BASE_URL = "https://api.mistral.ai/v1"

    def initialize(client: nil)
      @client = client
    end

    def response(model:, input:, prompt_cache_key: nil, response_schema: nil,
                 temperature: nil, max_output_tokens: nil)
      raw = client.chat.completions.create(
        request_parameters(
          model,
          input,
          prompt_cache_key,
          response_schema,
          temperature,
          max_output_tokens
        )
      )
      normalize(raw)
    rescue OpenAI::Errors::APITimeoutError => error
      raise TimeoutError.new(error.message, request_id: request_id_from(error)), cause: error
    rescue OpenAI::Errors::RateLimitError => error
      raise RateLimitError.new(error.message, request_id: request_id_from(error)), cause: error
    rescue OpenAI::Errors::APIError => error
      raise ProviderError.new(error.message, request_id: request_id_from(error)), cause: error
    end

    def stream_response(model:, input:, prompt_cache_key: nil)
      stream = client.chat.completions.stream(stream_parameters(model, input, prompt_cache_key))
      streamed_text = +""

      stream.each do |event|
        next unless event.type.to_s == "content.delta"

        streamed_text << event.delta
        yield event.delta if block_given?
      end

      normalize(
        stream.get_final_completion,
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

    def stream_parameters(model, input, prompt_cache_key)
      request_parameters(model, input, prompt_cache_key)
    end

    def request_parameters(model, input, prompt_cache_key, response_schema = nil,
                           temperature = nil, max_output_tokens = nil)
      {
        model: model,
        messages: serialize_input(input)
      }.tap do |parameters|
        parameters[:prompt_cache_key] = prompt_cache_key if prompt_cache_key.present?
        parameters[:response_format] = response_format(response_schema) if response_schema
        parameters[:temperature] = temperature unless temperature.nil?
        parameters[:max_tokens] = max_output_tokens unless max_output_tokens.nil?
        log_request(parameters)
      end
    end

    def response_format(response_schema)
      {
        type: "json_schema",
        json_schema: {
          name: response_schema.fetch(:name),
          strict: true,
          schema: response_schema.fetch(:schema)
        }
      }
    end

    def serialize_input(input)
      items = input.is_a?(Array) ? input : [ { role: "user", content: input } ]

      items.map do |item|
        role, content = if item.respond_to?(:role) && item.respond_to?(:content)
          [ item.role, item.content ]
        else
          [ item.fetch(:role), item.fetch(:content) ]
        end

        { role: serialized_role(role), content: content }
      end
    end

    def serialized_role(role)
      role.to_s == "developer" ? "system" : role
    end

    def provider_name
      "Mistral"
    end

    def client
      @client ||= OpenAI::Client.new(
        api_key: ENV.fetch("MISTRAL_API_KEY"),
        base_url: ENV.fetch("MISTRAL_BASE_URL", API_BASE_URL)
      )
    end

    def normalize(raw, fallback_text: nil, fallback_request_id: nil)
      raise MalformedResponseError, "Provider omitted the completed response" unless raw

      usage = raw.usage
      response = Response.new(
        text: completion_text(raw).presence || fallback_text,
        request_id: fallback_request_id.presence || response_request_id(raw),
        model: raw.model,
        usage: Usage.new(
          input_tokens: usage.prompt_tokens,
          cached_input_tokens: usage.prompt_tokens_details&.cached_tokens || 0,
          output_tokens: usage.completion_tokens
        )
      )
      log_response(response)
      response
    rescue NoMethodError, TypeError, ArgumentError => error
      raise MalformedResponseError.new("Provider returned an invalid response"), cause: error
    end

    def completion_text(response)
      content = response.choices.first.message.content
      return content if content.is_a?(String)

      Array(content).filter_map do |chunk|
        chunk.text if chunk.respond_to?(:text) && chunk.type.to_s == "text"
      end.join
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

    def log_request(parameters)
      Rails.logger.info(
        "#{provider_name} request model=#{parameters.fetch(:model)} " \
        "messages=#{parameters.fetch(:messages).length} " \
        "temperature=#{parameters.fetch(:temperature, "default")}"
      )
      return unless debug_payloads?

      Rails.logger.info("#{provider_name} request payload: #{redacted_parameters(parameters).inspect}")
    end

    def redacted_parameters(parameters)
      parameters.deep_dup.tap do |copy|
        copy.fetch(:messages).each do |message|
          next unless message[:content].is_a?(Array)

          message[:content].each do |part|
            next unless part[:type].to_s == "image_url"

            if part[:image_url].is_a?(Hash)
              part[:image_url][:url] = "[image data redacted]"
            else
              part[:image_url] = "[image data redacted]"
            end
          end
        end
      end
    end

    def log_response(response)
      cached_tokens = response.usage.cached_input_tokens
      input_tokens = response.usage.input_tokens
      cached_percent = input_tokens.positive? ? ((cached_tokens * 100.0) / input_tokens).round(1) : 0.0
      Rails.logger.info(
        "#{provider_name} response request_id=#{response.request_id} model=#{response.model} " \
        "input_tokens=#{input_tokens} cached_input_tokens=#{cached_tokens} " \
        "cache_hit=#{cached_tokens.positive?} cached_percent=#{cached_percent}"
      )
    end

    def debug_payloads?
      Rails.env.development? && ENV["AI_DEBUG_PAYLOADS"].to_s.casecmp?("true")
    end
  end
end
