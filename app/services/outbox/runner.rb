module Outbox
  class Runner
    POLL_INTERVAL = ENV.fetch("OUTBOX_POLL_INTERVAL", "1").to_f.clamp(0.1, 60.0)

    def self.call
      new.call
    end

    def call
      install_signal_handlers
      Rails.logger.info("Outbox dispatcher started")

      until @stopping
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
  end
end
