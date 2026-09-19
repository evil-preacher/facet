module Ai
  Usage = Data.define(:input_tokens, :cached_input_tokens, :output_tokens) do
    def initialize(input_tokens:, cached_input_tokens: 0, output_tokens:)
      super(
        input_tokens: Integer(input_tokens),
        cached_input_tokens: Integer(cached_input_tokens || 0),
        output_tokens: Integer(output_tokens)
      )
    end
  end

  Response = Data.define(:text, :request_id, :usage)

  class Error < StandardError
    attr_reader :request_id, :usage

    def initialize(message = nil, request_id: nil, usage: nil)
      @request_id = request_id
      @usage = usage
      super(message)
    end
  end

  class TimeoutError < Error; end
  class RateLimitError < Error; end
  class ProviderError < Error; end
  class MalformedResponseError < Error; end
  class PriceNotFoundError < Error; end
end
