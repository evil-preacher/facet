require "rails_helper"

RSpec.describe Ai::MemoryExtractionJob do
  it "delegates to the extraction service" do
    extraction = create(:memory_extraction)
    allow(Memories::Extract).to receive(:call)

    described_class.perform_now(extraction.id)

    expect(Memories::Extract).to have_received(:call).with(extraction: extraction)
  end

  it "retries a transient extraction failure" do
    extraction = create(:memory_extraction)
    allow(Memories::Extract).to receive(:call).and_raise(
      Ai::RetryableMemoryExtractionError.new(
        memory_extraction_id: extraction.id,
        error_code: "timeout"
      )
    )

    expect do
      described_class.perform_now(extraction.id)
    end.to have_enqueued_job(described_class).once
  end
end
