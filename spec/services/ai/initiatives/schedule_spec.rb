require "rails_helper"

RSpec.describe Ai::Initiatives::Schedule do
  let(:now) { Time.current }
  let(:personality) { create(:personality, :active, initiative_enabled: true) }
  let(:thread) { create(:conversation_thread, personality: personality) }

  it "creates one attempt and one outbox event for concurrent sweeps", :truncation do
    create(:message, conversation_thread: thread, created_at: now - 2.days)
    ready = Queue.new
    start = Queue.new
    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          described_class.call(personality: Personality.find(personality.id), now: now)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    workers.each(&:value)

    expect(personality.initiative_attempts.count).to eq(1)
    expect(OutboxEvent.where(event_key: "generate-initiative:#{personality.initiative_attempts.first.id}").count).to eq(1)
  end
end
