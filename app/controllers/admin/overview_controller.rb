module Admin
  class OverviewController < ApplicationController
    def index
      @counts = {
        users: User.count,
        personalities: Personality.count,
        generation_runs: GenerationRun.count,
        model_calls: ModelCall.count,
        initiative_attempts: InitiativeAttempt.count,
        pending_outbox: OutboxEvent.pending.count
      }
      month_calls = ModelCall.where(created_at: Ai::SpendingBudget.month_range(Time.current))
      @budget_limit_microusd = User.sum(:monthly_ai_limit_microusd)
      @model_cost_microusd = month_calls.sum(:cost_microusd)
      @model_reserved_microusd = month_calls.sum(:reserved_cost_microusd)
      @global_limit_microusd = Ai::SpendingBudget.global_limit
      @queues = sidekiq_queues
      AdminAuditEvent.create!(actor_user_id: current_admin.id, action: "index", target_type: "AdminOverview")
    end

    private

    def sidekiq_queues
      Sidekiq::Queue.all.map { |queue| [ queue.name, queue.size, queue.latency.round(1) ] }
    rescue RedisClient::Error
      nil
    end
  end
end
