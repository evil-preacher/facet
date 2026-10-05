module Ai
  class SpendingBudget
    DEFAULT_GLOBAL_LIMIT_MICROUSD = 100_000_000
    WARNING_PERCENT = 80
    RESERVATION_TTL = 1.hour
    DEFAULT_MAX_OUTPUT_TOKENS = 4_096
    IMAGE_TOKEN_ESTIMATE = 10_000

    Snapshot = Data.define(:month_start, :month_end, :spent, :reserved, :user_limit, :global_limit) do
      def remaining = [ user_limit - spent - reserved, 0 ].max
      def warning? = user_limit.positive? && (spent + reserved) * 100 >= user_limit * WARNING_PERCENT
    end

    def self.global_limit
      Integer(ENV.fetch("AI_GLOBAL_MONTHLY_LIMIT_MICROUSD", DEFAULT_GLOBAL_LIMIT_MICROUSD))
    end

    def self.month_range(now)
      start = now.in_time_zone(Time.zone).beginning_of_month
      start...start.next_month
    end

    def self.snapshot(user:, now: Time.current)
      range = month_range(now)
      calls = ModelCall.where(user: user, created_at: range)
      Snapshot.new(
        month_start: range.begin, month_end: range.end,
        spent: calls.sum(:cost_microusd), reserved: calls.sum(:reserved_cost_microusd),
        user_limit: user.monthly_ai_limit_microusd, global_limit: global_limit
      )
    end

    def self.reserve!(user:, personality:, generation_run:, purpose:, provider:, model:, price:, input:,
                      response_schema:, max_output_tokens:, now:)
      amount = estimate(price: price, input: input, response_schema: response_schema,
                        max_output_tokens: max_output_tokens)
      range = month_range(now)
      ModelCall.transaction do
        lock = AiBudgetLock.find_or_create_by!(id: 1)
        lock.lock!
        user.lock!
        active = ModelCall.where(created_at: range)
        global_total = active.sum(:cost_microusd) + active.sum(:reserved_cost_microusd)
        user_active = active.where(user: user)
        user_total = user_active.sum(:cost_microusd) + user_active.sum(:reserved_cost_microusd)
        raise BudgetExceededError if amount > global_limit - global_total ||
                                     amount > user.monthly_ai_limit_microusd - user_total

        ModelCall.create!(
          user: user, personality: personality, generation_run: generation_run,
          purpose: purpose, provider: provider, model: model, status: :pending,
          reserved_cost_microusd: amount, reservation_expires_at: now + RESERVATION_TTL,
          created_at: now
        )
      end
    end

    def self.estimate(price:, input:, response_schema:, max_output_tokens:)
      input_tokens = content_size(input) + content_size(response_schema)
      CostCalculator.call(price: price, input_tokens: input_tokens, cached_input_tokens: 0,
                          output_tokens: max_output_tokens)
    end

    def self.content_size(value)
      case value
      when String then value.length
      when Array then value.sum { |item| content_size(item) }
      when Hash
        value.sum do |key, item|
          key.to_s.match?(/image|url/) ? IMAGE_TOKEN_ESTIMATE : content_size(item)
        end
      else
        if value.respond_to?(:content)
          content_size(value.content)
        else
          value.to_s.length
        end
      end
    end
    private_class_method :content_size
  end
end
