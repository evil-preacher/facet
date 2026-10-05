require "rails_helper"

RSpec.describe Ai::ReleaseExpiredReservationsJob do
  it "releases an expired pending reservation without changing completed usage" do
    now = Time.current
    stale = create(:model_call, reserved_cost_microusd: 5_000, reservation_expires_at: now - 1.minute)
    fresh = create(:model_call, reserved_cost_microusd: 5_000, reservation_expires_at: now + 1.hour)

    described_class.new.perform(now)

    expect(stale.reload).to have_attributes(status: "failed", reserved_cost_microusd: 0,
                                            error_code: "reservation_expired")
    expect(fresh.reload).to have_attributes(status: "pending", reserved_cost_microusd: 5_000)
  end
end
