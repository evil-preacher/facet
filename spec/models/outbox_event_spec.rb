require "rails_helper"

RSpec.describe OutboxEvent, type: :model do
  subject(:event) do
    described_class.new(
      event_key: "event-1",
      job_class: "Ai::GenerateReplyJob",
      queue_name: "conversation",
      arguments: [ 1 ],
      available_at: Time.current
    )
  end

  it { is_expected.to validate_presence_of(:event_key) }
  it { is_expected.to validate_uniqueness_of(:event_key) }
  it { is_expected.to validate_numericality_of(:attempts_count).only_integer.is_greater_than_or_equal_to(0) }

  it "requires array arguments" do
    event.arguments = { "id" => 1 }

    expect(event).not_to be_valid
  end
end
