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

  Response = Data.define(:text, :request_id, :model, :usage)

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
  class StoppedError < Error; end
  class ValidationError < Error; end
  class BudgetExceededError < Error; end

  class RetryableGenerationError < StandardError
    attr_reader :generation_run_id, :error_code

    def initialize(generation_run_id:, error_code:)
      @generation_run_id = generation_run_id
      @error_code = error_code
      super("Retryable generation failure: #{error_code}")
    end
  end
end
