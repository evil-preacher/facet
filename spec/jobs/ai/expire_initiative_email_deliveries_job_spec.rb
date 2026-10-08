require "rails_helper"

RSpec.describe Ai::ExpireInitiativeEmailDeliveriesJob do
  it "marks an ambiguous old claim unknown without resending" do
    personality = create(:personality, :active, user: create(:user, :confirmed))
    thread = create(:conversation_thread, personality: personality)
    source = create(:message, conversation_thread: thread)
    attempt = create(:initiative_attempt, personality: personality, conversation_thread: thread,
                     source_message: source)
    delivery = InitiativeEmailDelivery.create!(initiative_attempt: attempt, status: :sending,
                                               claimed_at: 2.hours.ago)

    expect { described_class.perform_now }.not_to change(ActionMailer::Base.deliveries, :size)
    expect(delivery.reload).to have_attributes(status: "unknown", error_code: "delivery_result_unknown")
  end
end
