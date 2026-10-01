module Ai
  class Gateway
    class << self
      def default
        @default ||= ProviderRegistry.gateway_for(Rails.configuration.x.ai.provider)
      end

      attr_writer :default
    end

    def initialize(adapter:)
      @adapter = adapter
    end

    def response(model:, input:, prompt_cache_key: nil, response_schema: nil,
                 temperature: nil, max_output_tokens: nil)
      validate_response!(
        @adapter.response(
          **request_arguments(
            model,
            input,
            prompt_cache_key,
            response_schema,
            temperature,
            max_output_tokens
          )
        )
      )
    end

    def stream_response(model:, input:, prompt_cache_key: nil, &on_delta)
      validate_response!(
        @adapter.stream_response(**request_arguments(model, input, prompt_cache_key), &on_delta)
      )
    end

    private

    def request_arguments(model, input, prompt_cache_key, response_schema = nil,
                          temperature = nil, max_output_tokens = nil)
      { model: model, input: input }.tap do |arguments|
        arguments[:prompt_cache_key] = prompt_cache_key if prompt_cache_key.present?
        arguments[:response_schema] = response_schema if response_schema.present?
        arguments[:temperature] = temperature unless temperature.nil?
        arguments[:max_output_tokens] = max_output_tokens unless max_output_tokens.nil?
      end
    end

    def validate_response!(response)
      valid = response.is_a?(Response) &&
        response.text.is_a?(String) && response.text.present? &&
        response.request_id.present? && response.model.present? && response.usage.is_a?(Usage) &&
        response.usage.input_tokens >= 0 &&
        response.usage.cached_input_tokens.between?(0, response.usage.input_tokens) &&
        response.usage.output_tokens >= 0
      return response if valid

      raise MalformedResponseError, "Provider returned an invalid response"
    end
  end
end
