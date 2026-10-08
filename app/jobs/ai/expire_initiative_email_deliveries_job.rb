module Ai
  class ExpireInitiativeEmailDeliveriesJob < ApplicationJob
    queue_as :maintenance

    def perform
      InitiativeEmailDelivery.sending.where("claimed_at < ?", 1.hour.ago).find_each do |delivery|
        delivery.with_lock do
          delivery.update!(status: :unknown, error_code: "delivery_result_unknown") if delivery.sending? &&
            delivery.claimed_at < 1.hour.ago
        end
      end
    end
  end
end
