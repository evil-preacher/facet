require "rails_helper"

RSpec.describe MessageAttachment, type: :model do
  subject(:attachment) { build(:message_attachment) }

  it { is_expected.to belong_to(:message) }
  it { is_expected.to validate_presence_of(:object_key) }
  it "requires a unique object key" do
    existing = create(:message_attachment)
    duplicate = build(:message_attachment, object_key: existing.object_key)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:object_key]).to be_present
  end

  it "only belongs to a user message" do
    attachment = build(:message_attachment, message: build(:message, :assistant))

    expect(attachment).not_to be_valid
    expect(attachment.errors[:message]).to be_present
  end
end
