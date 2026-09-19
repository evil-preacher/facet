require "rails_helper"

RSpec.describe ModelPrice, type: :model do
  subject(:model_price) { build(:model_price) }

  it { is_expected.to validate_presence_of(:provider) }
  it { is_expected.to validate_presence_of(:model) }
  it { is_expected.to validate_presence_of(:version) }
  it { is_expected.to validate_uniqueness_of(:effective_from).scoped_to(:provider, :model) }
  it { is_expected.to validate_numericality_of(:input_microusd_per_million).only_integer.is_greater_than_or_equal_to(0) }
  it { is_expected.to validate_numericality_of(:cached_input_microusd_per_million).only_integer.is_greater_than_or_equal_to(0) }
  it { is_expected.to validate_numericality_of(:output_microusd_per_million).only_integer.is_greater_than_or_equal_to(0) }

  it "rejects an inverted effective interval" do
    model_price.effective_until = model_price.effective_from

    expect(model_price).not_to be_valid
    expect(model_price.errors[:effective_until]).to be_present
  end
end
