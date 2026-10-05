module Operations
  class HealthController < BaseController
    def show
      database_ok = ActiveRecord::Base.connection.active?
      redis_ok = Sidekiq.redis { |connection| connection.call("PING") == "PONG" }
      stats = Sidekiq::Stats.new

      render json: {
        status: database_ok && redis_ok ? "ok" : "degraded",
        database: database_ok ? "ok" : "unavailable",
        redis: redis_ok ? "ok" : "unavailable",
        sidekiq: {
          processes: stats.processes_size,
          enqueued: stats.enqueued,
          scheduled: stats.scheduled_size,
          retries: stats.retry_size,
          dead: stats.dead_size,
          queues: queue_metrics
        },
        outbox: {
          pending: OutboxEvent.pending.count,
          oldest_pending_seconds: oldest_pending_seconds
        }
      }, status: database_ok && redis_ok ? :ok : :service_unavailable
    rescue RedisClient::Error
      render json: { status: "degraded", database: "ok", redis: "unavailable" },
             status: :service_unavailable
    end

    private

    def queue_metrics
      Sidekiq::Queue.all.index_with do |queue|
        { depth: queue.size, latency_seconds: queue.latency.round(3) }
      end.transform_keys(&:name)
    end

    def oldest_pending_seconds
      created_at = OutboxEvent.pending.minimum(:created_at)
      ((Time.current - created_at).round if created_at)
    end
  end
end
