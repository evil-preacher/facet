require "rails_helper"

RSpec.describe ApplicationHelper do
  subject(:helper_instance) { Class.new { include ApplicationHelper }.new }

  describe "#personality_avatar_url" do
    it "keeps an existing avatar visible while its replacement has failed" do
      personality = build_stubbed(
        :personality,
        avatar_status: :failed,
        avatar_object_key: "personalities/1/avatars/version-1.png"
      )
      storage = instance_double(ObjectStorage::S3Store)
      allow(ObjectStorage::S3Store).to receive(:default).and_return(storage)
      allow(storage).to receive(:presigned_url).and_return("https://example.test/avatar.png")

      expect(helper_instance.personality_avatar_url(personality)).to eq("https://example.test/avatar.png")
      expect(storage).to have_received(:presigned_url).with(key: personality.avatar_object_key)
    end
  end
end
