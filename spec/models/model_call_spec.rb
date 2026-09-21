require "rails_helper"

RSpec.describe ModelCall, type: :model do
  subject(:model_call) { build(:model_call) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:personality).optional }
  it { is_expected.to belong_to(:generation_run).optional }
  it do
    expect(model_call).to define_enum_for(:purpose)
      .with_values(
        conversation: "conversation",
        memory_extraction: "memory_extraction",
        memory_consolidation: "memory_consolidation",
        thread_summary: "thread_summary",
        initiative: "initiative",
        photo_planning: "photo_planning"
      )
      .backed_by_column_of_type(:string)
  end
  it do
    expect(model_call).to define_enum_for(:status)
      .with_values(pending: "pending", completed: "completed", failed: "failed")
      .backed_by_column_of_type(:string)
  end
  it { is_expected.to validate_presence_of(:provider) }
  it { is_expected.to validate_presence_of(:model) }
  it { is_expected.to validate_numericality_of(:input_tokens).only_integer.is_greater_than_or_equal_to(0).allow_nil }
  it { is_expected.to validate_numericality_of(:cached_input_tokens).only_integer.is_greater_than_or_equal_to(0).allow_nil }
  it { is_expected.to validate_numericality_of(:output_tokens).only_integer.is_greater_than_or_equal_to(0).allow_nil }
  it { is_expected.to validate_numericality_of(:cost_microusd).only_integer.is_greater_than_or_equal_to(0).allow_nil }

  it "does not allow cached input to exceed total input" do
    model_call.input_tokens = 4
    model_call.cached_input_tokens = 5

    expect(model_call).not_to be_valid
    expect(model_call.errors[:cached_input_tokens]).to be_present
  end

  it "requires usage and pricing data when completed" do
    model_call.status = :completed
    model_call.input_tokens = nil
    model_call.output_tokens = nil
    model_call.cost_microusd = nil
    model_call.pricing_version = nil

    expect(model_call).not_to be_valid
  end
end
