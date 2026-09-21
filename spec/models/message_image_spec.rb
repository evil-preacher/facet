require "rails_helper"

RSpec.describe MessageImage do
  it "only belongs to an assistant message" do
    image = build(:message_image, message: build(:message))

    expect(image).not_to be_valid
    expect(image.errors[:message]).to be_present
  end

  it "requires object metadata when ready" do
    image = build(:message_image, status: :ready)

    expect(image).not_to be_valid
    expect(image.errors[:object_key]).to be_present
  end
end
