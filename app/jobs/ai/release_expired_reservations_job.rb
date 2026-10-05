module Ai
  class ReleaseExpiredReservationsJob < ApplicationJob
    queue_as :maintenance

    def perform(now = Time.current)
      ModelCall.where(status: :pending).where("reserved_cost_microusd > 0 AND reservation_expires_at <= ?", now)
        .find_each do |call|
          call.with_lock do
            next unless call.pending? && call.reserved_cost_microusd.positive? &&
              call.reservation_expires_at <= now

            call.update!(status: :failed, error_code: "reservation_expired",
                         error_message: "Model request expired", completed_at: now,
                         reserved_cost_microusd: 0, reservation_expires_at: nil)
          end
        end
    end
  end
end
