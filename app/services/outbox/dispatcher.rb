module Outbox
  class Dispatcher
    LOCK_TIMEOUT = 5.minutes
    MAX_BACKOFF = 5.minutes

    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(limit: 25, event_ids: nil, now: Time.current)
      @limit = limit
      @event_ids = event_ids
      @now = now
    end

    def call
      recover_stale_locks!
      dispatched = 0

      limit.times do
        event = claim_next
        break unless event

        dispatch(event)
        dispatched += 1
      end

      dispatched
    end

    private

    attr_reader :limit, :event_ids, :now

    def recover_stale_locks!
      scope.where(status: :processing, locked_at: ...now - LOCK_TIMEOUT).update_all(
        status: OutboxEvent.statuses.fetch("pending"),
        locked_at: nil,
        updated_at: now
      )
    end

    def claim_next
      OutboxEvent.transaction do
        event = scope.ready(now).order(:available_at, :id).lock("FOR UPDATE SKIP LOCKED").first
        next unless event

        event.update!(
          status: :processing,
          locked_at: now,
          attempts_count: event.attempts_count + 1
        )
        event
      end
    end

    def dispatch(event)
      event.job_class.constantize.set(queue: event.queue_name).perform_later(*event.arguments)
      event.update!(status: :dispatched, dispatched_at: now, locked_at: nil, last_error: nil)
    rescue StandardError => error
      event.update!(
        status: :pending,
        available_at: now + backoff(event.attempts_count),
        locked_at: nil,
        last_error: safe_error(error)
      )
    end

    def scope
      relation = OutboxEvent.all
      event_ids ? relation.where(id: event_ids) : relation
    end

    def backoff(attempt)
      [ 2**[ attempt, 8 ].min, MAX_BACKOFF.to_i ].min.seconds
    end

    def safe_error(error)
      "#{error.class}: #{error.message}".truncate(1_000)
    end
  end
end
