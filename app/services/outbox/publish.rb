module Outbox
  class Publish
    def self.call(event_key:, job_class:, arguments:, queue_name: job_class.queue_name, now: Time.current)
      OutboxEvent.create_or_find_by!(event_key: event_key) do |event|
        event.job_class = job_class.name
        event.queue_name = queue_name
        event.arguments = arguments
        event.available_at = now
      end
    end
  end
end
