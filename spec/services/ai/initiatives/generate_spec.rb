require "rails_helper"
require_relative "../../../support/ai/fake_adapter"

RSpec.describe Ai::Initiatives::Generate do
  let(:now) { Time.current }
  let(:personality) { create(:personality, :active, initiative_enabled: true) }
  let(:thread) { create(:conversation_thread, personality: personality) }
  let!(:source) { create(:message, conversation_thread: thread, content: "How are you?", created_at: now - 2.days) }
  let(:attempt) { create(:initiative_attempt, personality: personality, conversation_thread: thread,
                        source_message: source, created_at: now - 1.minute) }
  let(:adapter) { Ai::FakeAdapter.new }
  let(:gateway) { Ai::Gateway.new(adapter: adapter) }

  before do
    create(:model_price, model: personality.utility_model, effective_from: now - 1.day)
    create(:model_price, model: personality.conversation_model, effective_from: now - 1.day)
  end

  def generate
    described_class.call(attempt: attempt, gateway: gateway, now: now)
  end

  it "creates one unread assistant message after a positive decision" do
    adapter.enqueue_response(text: '{"send_message":true,"channel":"in_app","topic":"Ask about the book","motivation":"Interest in the book","intensity":"low"}',
                             request_id: "decision-1", usage: Ai::Usage.new(input_tokens: 100, output_tokens: 20))
    adapter.enqueue_response(text: "Hello! How was that book?", request_id: "initiative-1",
                             usage: Ai::Usage.new(input_tokens: 200, output_tokens: 30))

    result = generate

    expect(result.status).to eq(:completed)
    expect(result.message).to have_attributes(role: "assistant", initiated_by: "personality", read_at: nil)
    expect(thread.reload.last_message_at).to eq(result.message.created_at)
    expect(attempt.reload).to have_attributes(status: "completed", topic: "Ask about the book")
    expect(ModelCall.where(purpose: "initiative").count).to eq(2)
    expect { generate }.not_to change(Message, :count)
  end

  it "does not send a message when the decision declines" do
    adapter.enqueue_response(text: '{"send_message":false,"channel":"none","topic":"","motivation":"","intensity":"low"}',
                             request_id: "decision-2", usage: Ai::Usage.new(input_tokens: 100, output_tokens: 20))
    expect { generate }.not_to change(Message, :count)
    expect(attempt.reload).to be_skipped
    expect(attempt.decision).to eq("NO_ACTION")
  end

  it "does not send if the user replies while models are running" do
    adapter.enqueue_response(text: '{"send_message":true,"channel":"in_app","topic":"Greeting","motivation":"A quick check-in","intensity":"low"}',
                             request_id: "decision-3", usage: Ai::Usage.new(input_tokens: 100, output_tokens: 20))
    adapter.enqueue_raw_response(Ai::Response.new(text: "Hello!", request_id: "initiative-3",
      model: personality.conversation_model, usage: Ai::Usage.new(input_tokens: 100, output_tokens: 20)))
    allow(gateway).to receive(:response).and_wrap_original do |original, **args|
      response = original.call(**args)
      create(:message, conversation_thread: thread, content: "I am back", created_at: now) if adapter.requests.size == 2
      response
    end

    expect { generate }.to change(Message, :count).by(1)
    expect(attempt.reload).to be_skipped
    expect(thread.messages.unread_initiatives).to be_empty
  end

  it "skips when the remaining budget cannot cover the decision call" do
    personality.user.update!(monthly_ai_limit_microusd: 1)

    expect(generate.status).to eq(:skipped)
    expect(adapter.requests).to be_empty
    expect(thread.messages.unread_initiatives).to be_empty
  end

  it "honors the owner disabling initiative after the decision" do
    adapter.enqueue_response(text: '{"send_message":true,"channel":"in_app","topic":"Greeting","motivation":"A quick check-in","intensity":"low"}',
                             request_id: "decision-4", usage: Ai::Usage.new(input_tokens: 100, output_tokens: 20))
    allow(gateway).to receive(:response).and_wrap_original do |original, **args|
      response = original.call(**args)
      personality.update!(initiative_enabled: false)
      response
    end

    expect(generate.status).to eq(:skipped)
    expect(adapter.requests.size).to eq(1)
    expect(thread.messages.unread_initiatives).to be_empty
  end

  it "records NO_ACTION during quiet hours without calling a model" do
    hour = now.in_time_zone("UTC").hour
    personality.update!(initiative_quiet_start_hour: hour,
                        initiative_quiet_end_hour: (hour + 1) % 24)

    result = generate

    expect(result.status).to eq(:skipped)
    expect(attempt.reload).to have_attributes(decision: "NO_ACTION", decision_reason: "quiet_hours")
    expect(adapter.requests).to be_empty
  end

  it "vetoes a high-intensity decision for a quiet setting before message generation" do
    adapter.enqueue_response(text: '{"send_message":true,"channel":"in_app","topic":"Talk","motivation":"Strong desire to reach out","intensity":"high"}',
                             request_id: "decision-high", usage: Ai::Usage.new(input_tokens: 100, output_tokens: 20))

    result = generate

    expect(result.status).to eq(:skipped)
    expect(attempt.reload).to have_attributes(decision: "NO_ACTION", decision_reason: "intensity_limit")
    expect(adapter.requests.size).to eq(1)
    expect(thread.messages.unread_initiatives).to be_empty
  end

  it "queues one email delivery only after a permitted email decision" do
    personality.update!(initiative_email_enabled: true)
    personality.user.update!(confirmed_at: now)
    adapter.enqueue_response(text: '{"send_message":true,"channel":"email","topic":"Book","motivation":"Ask about the book","intensity":"low"}',
                             request_id: "decision-email", usage: Ai::Usage.new(input_tokens: 100, output_tokens: 20))
    adapter.enqueue_response(text: "Hello! How was that book?", request_id: "email-message",
                             usage: Ai::Usage.new(input_tokens: 200, output_tokens: 30))

    expect { generate }.to change(InitiativeEmailDelivery, :count).by(1)
    expect(attempt.reload).to have_attributes(status: "completed", decision: "EMAIL")
    expect(attempt.initiative_email_delivery).to be_pending
    expect(OutboxEvent.exists?(event_key: "deliver-initiative-email:#{attempt.id}")).to be(true)
  end

  it "blocks a model-selected email channel without explicit owner consent" do
    adapter.enqueue_response(text: '{"send_message":true,"channel":"email","topic":"Book","motivation":"Ask about the book","intensity":"low"}',
                             request_id: "decision-unallowed-email", usage: Ai::Usage.new(input_tokens: 100, output_tokens: 20))

    expect { generate }.not_to change(InitiativeEmailDelivery, :count)
    expect(attempt.reload).to have_attributes(status: "skipped", decision: "NO_ACTION",
                                              decision_reason: "email_disabled")
    expect(adapter.requests.size).to eq(1)
  end
end
