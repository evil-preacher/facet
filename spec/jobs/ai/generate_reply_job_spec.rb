require "rails_helper"

RSpec.describe Ai::GenerateReplyJob do
  it "delegates a persisted run to the generation service" do
    generation_run = create(:generation_run)
    result = instance_double(Ai::GenerateReply::Result)

    allow(Ai::GenerateReply).to receive(:call).and_return(result)

    described_class.perform_now(generation_run.id)

    expect(Ai::GenerateReply).to have_received(:call).with(generation_run: generation_run)
  end
end
