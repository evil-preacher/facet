module Outbox
  class Runner
    POLL_INTERVAL = ENV.fetch("OUTBOX_POLL_INTERVAL", "1").to_f.clamp(0.1, 60.0)

    def self.call
      new.call
    end

    def call
      install_signal_handlers
      Rails.logger.info("Outbox dispatcher started")
      next_budget_maintenance = Time.current
      next_initiative_sweep = Time.current
      next_privacy_retention = Time.current
      next_dynamic_decay = Time.current
      next_email_delivery_audit = Time.current

      until @stopping
        if Time.current >= next_budget_maintenance
          next_budget_maintenance = enqueue_maintenance(Ai::ReleaseExpiredReservationsJob, 5.minutes)
        end
        if Time.current >= next_initiative_sweep
          next_initiative_sweep = enqueue_maintenance(Ai::InitiativeSweepJob, 30.minutes)
        end
        if Time.current >= next_privacy_retention
          next_privacy_retention = enqueue_maintenance(Privacy::RetentionJob, 1.day)
        end
        if Time.current >= next_dynamic_decay
          next_dynamic_decay = enqueue_maintenance(Ai::DynamicStateDecayJob, 1.hour)
        end
        if Time.current >= next_email_delivery_audit
          next_email_delivery_audit = enqueue_maintenance(Ai::ExpireInitiativeEmailDeliveriesJob, 1.hour)
        end
        count = Dispatcher.call
        sleep(POLL_INTERVAL) if count.zero?
      end
    ensure
      Rails.logger.info("Outbox dispatcher stopped")
    end

    private

    def install_signal_handlers
      @stopping = false
      %w[INT TERM].each { |signal| Signal.trap(signal) { @stopping = true } }
    end

    def enqueue_maintenance(job_class, interval)
      job_class.perform_later
      Time.current + interval
    rescue StandardError => error
      Rails.logger.warn("Maintenance enqueue failed job=#{job_class.name} error=#{error.class.name}")
      Time.current + 1.minute
    end
  end
end
