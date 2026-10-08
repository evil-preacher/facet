module Ai
  class DeliverInitiativeEmailJob < ApplicationJob
    queue_as :initiative
    discard_on ActiveJob::DeserializationError

    def perform(delivery_id)
      delivery = InitiativeEmailDelivery.find_by(id: delivery_id)
      Ai::Initiatives::EmailDelivery.call(delivery: delivery) if delivery
    end
  end
end
