require "rails_helper"

RSpec.describe MemorySource do
  it "rejects a source message from another personality" do
    memory = create(:memory)
    foreign_message = create(:message)

    source = build(:memory_source, memory: memory, message: foreign_message)

    expect(source).not_to be_valid
    expect(source.errors[:message]).to be_present
  end
end
