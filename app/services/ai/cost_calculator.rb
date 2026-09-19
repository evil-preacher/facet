module Ai
  class CostCalculator
    MICROS_PER_MILLION_TOKENS = 1_000_000

    def self.call(price:, input_tokens:, cached_input_tokens:, output_tokens:)
      new(
        price: price,
        input_tokens: input_tokens,
        cached_input_tokens: cached_input_tokens,
        output_tokens: output_tokens
      ).call
    end

    def initialize(price:, input_tokens:, cached_input_tokens:, output_tokens:)
      @price = price
      @input_tokens = Integer(input_tokens)
      @cached_input_tokens = Integer(cached_input_tokens || 0)
      @output_tokens = Integer(output_tokens)
    end

    def call
      validate_usage!
      numerator = uncached_input_tokens * @price.input_microusd_per_million
      numerator += @cached_input_tokens * @price.cached_input_microusd_per_million
      numerator += @output_tokens * @price.output_microusd_per_million
      (numerator + MICROS_PER_MILLION_TOKENS - 1) / MICROS_PER_MILLION_TOKENS
    end

    private

    def uncached_input_tokens
      @input_tokens - @cached_input_tokens
    end

    def validate_usage!
      values = [ @input_tokens, @cached_input_tokens, @output_tokens ]
      raise ArgumentError, "Token counts must be nonnegative" if values.any?(&:negative?)
      raise ArgumentError, "Cached input exceeds input" if @cached_input_tokens > @input_tokens
    end
  end
end
