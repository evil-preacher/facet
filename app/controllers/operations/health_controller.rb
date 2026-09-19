module Operations
  class HealthController < ApplicationController
    skip_before_action :set_current_user
    skip_around_action :switch_locale
    before_action :authenticate_operator!

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

    def authenticate_operator!
      username = ENV["OPERATIONS_USERNAME"]
      password = ENV["OPERATIONS_PASSWORD"]
      return head :not_found if username.blank? || password.blank?

      authenticate_or_request_with_http_basic("Facet operations") do |given_username, given_password|
        ActiveSupport::SecurityUtils.secure_compare(given_username, username) &
          ActiveSupport::SecurityUtils.secure_compare(given_password, password)
      end
    end

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
