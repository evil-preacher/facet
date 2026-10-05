module Ai
  class UsageReport
    Result = Data.define(:snapshot, :by_day, :by_purpose, :by_personality, :tokens)

    def self.call(user:, now: Time.current)
      snapshot = SpendingBudget.snapshot(user: user, now: now)
      calls = user.model_calls.where(created_at: snapshot.month_start...snapshot.month_end)
      rows = calls.pluck(:created_at, :purpose, :personality_id, :cost_microusd,
                         :input_tokens, :cached_input_tokens, :output_tokens)
      by_day = Hash.new(0)
      by_purpose = Hash.new(0)
      by_personality = Hash.new(0)
      tokens = { input: 0, cached: 0, output: 0 }
      rows.each do |created_at, purpose, personality_id, cost, input, cached, output|
        by_day[created_at.in_time_zone(Time.zone).to_date] += cost.to_i
        by_purpose[purpose] += cost.to_i
        by_personality[personality_id] += cost.to_i
        tokens[:input] += input.to_i
        tokens[:cached] += cached.to_i
        tokens[:output] += output.to_i
      end
      Result.new(snapshot: snapshot, by_day: by_day.sort.reverse.to_h,
                 by_purpose: by_purpose, by_personality: by_personality, tokens: tokens)
    end
  end
end
