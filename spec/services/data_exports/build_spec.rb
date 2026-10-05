require "rails_helper"

RSpec.describe DataExports::Build do
  it "includes uploaded image bytes in the account export" do
    user = create(:user, :confirmed)
    personality = create(:personality, :active, user: user)
    thread = create(:conversation_thread, personality: personality)
    message = create(:message, conversation_thread: thread)
    create(:message_attachment, message: message, object_key: "private/photo.jpg")
    storage = instance_double(ObjectStorage::S3Store)
    allow(storage).to receive(:download).with(key: "private/photo.jpg").and_return("photo bytes")

    exported = described_class.call(user: user, storage: storage)
    attachment = exported.fetch(:personalities).first.fetch(:threads).first.fetch(:messages).first.fetch(:attachment)

    expect(Base64.decode64(attachment.fetch(:data_base64))).to eq("photo bytes")
  end
end
