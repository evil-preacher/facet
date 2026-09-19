module Ai
  class Gateway
    class << self
      def default
        @default ||= new(adapter: OpenAiAdapter.new)
      end

      attr_writer :default
    end

    def initialize(adapter:)
      @adapter = adapter
    end

    def response(model:, input:)
      validate_response!(@adapter.response(model: model, input: input))
    end

    def stream_response(model:, input:, &on_delta)
      validate_response!(@adapter.stream_response(model: model, input: input, &on_delta))
    end

    private

    def validate_response!(response)
      valid = response.is_a?(Response) &&
        response.text.is_a?(String) && response.text.present? &&
        response.request_id.present? && response.usage.is_a?(Usage) &&
        response.usage.input_tokens >= 0 &&
        response.usage.cached_input_tokens.between?(0, response.usage.input_tokens) &&
        response.usage.output_tokens >= 0
      return response if valid

      raise MalformedResponseError, "Provider returned an invalid response"
    end
  end
end
