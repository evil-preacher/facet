require "rails_helper"

RSpec.describe Ai::Initiatives::EmailDelivery do
  let(:now) { Time.zone.parse("2026-10-08 12:00:00 UTC") }
  let(:personality) do
    create(:personality, :active, user: create(:user, :confirmed),
           initiative_enabled: true, initiative_email_enabled: true,
           initiative_timezone: "UTC", initiative_quiet_start_hour: 22, initiative_quiet_end_hour: 8)
  end
  let(:thread) { create(:conversation_thread, personality: personality) }
  let(:source) { create(:message, conversation_thread: thread, created_at: now - 2.days) }
  let(:message) { create(:message, :assistant, conversation_thread: thread, initiated_by: "personality") }
  let(:attempt) do
    create(:initiative_attempt, personality: personality, conversation_thread: thread,
           source_message: source, message: message, status: :completed, decision: "EMAIL",
           topic: "Check in", motivation: "They discussed a book earlier", intensity: "low",
           completed_at: now)
  end
  let(:delivery) { InitiativeEmailDelivery.create!(initiative_attempt: attempt) }

  it "sends one email for repeated deliveries and records the result" do
    expect { described_class.call(delivery: delivery, now: now) }
      .to change(ActionMailer::Base.deliveries, :size).by(1)
    expect(delivery.reload).to have_attributes(status: "delivered", delivered_at: now)
    expect { described_class.call(delivery: delivery, now: now) }
      .not_to change(ActionMailer::Base.deliveries, :size)
    expect(ActionMailer::Base.deliveries.last.body.decoded).to include(message.content)
  end

  it "sends once when two workers retry the same delivery concurrently", :truncation do
    delivery_id = delivery.id
    ready = Queue.new
    start = Queue.new
    sent_before = ActionMailer::Base.deliveries.size
    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          described_class.call(delivery: InitiativeEmailDelivery.find(delivery_id), now: now)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    workers.each(&:value)

    expect(ActionMailer::Base.deliveries.size - sent_before).to eq(1)
    expect(delivery.reload).to be_delivered
  end

  it "uses the conversation language for the email" do
    message.update!(content: "Hello! How are you?", language: "en")

    described_class.call(delivery: delivery, now: now)

    mail = ActionMailer::Base.deliveries.last
    expect(mail.subject).to include("A message from")
    expect(mail.body.decoded).to include("Hello! How are you?", "Open conversation")
  end

  it "suppresses delivery immediately after the owner disables email" do
    delivery
    personality.update!(initiative_email_enabled: false)

    expect { described_class.call(delivery: delivery, now: now) }
      .not_to change(ActionMailer::Base.deliveries, :size)
    expect(delivery.reload).to have_attributes(status: "suppressed", error_code: "email_disabled")
  end

  it "suppresses delivery when quiet hours begin before the job runs" do
    delivery

    expect { described_class.call(delivery: delivery, now: now.change(hour: 23)) }
      .not_to change(ActionMailer::Base.deliveries, :size)
    expect(delivery.reload).to have_attributes(status: "suppressed", error_code: "quiet_hours")
  end

  it "records an SMTP failure and never automatically retries an ambiguous send" do
    delivery
    mailer = instance_double(ActionMailer::MessageDelivery)
    allow(UserMailer).to receive(:with).and_return(double(initiative_email: mailer))
    allow(mailer).to receive(:deliver_now).and_raise(Net::SMTPServerBusy)

    expect { described_class.call(delivery: delivery, now: now) }
      .not_to change(ActionMailer::Base.deliveries, :size)
    expect(delivery.reload).to have_attributes(status: "unknown", error_code: "delivery_result_unknown")
    described_class.call(delivery: delivery, now: now)
    expect(mailer).to have_received(:deliver_now).once
  end

  it "removes delivery audit and pending outbox work with the personality" do
    delivery
    Outbox::Publish.call(event_key: "deliver-initiative-email:#{attempt.id}",
                         job_class: Ai::DeliverInitiativeEmailJob, arguments: [ delivery.id ])

    expect do
      Personalities::Destroy.call(user: personality.user, personality: personality)
    end.to change(InitiativeEmailDelivery, :count).by(-1)
    expect(OutboxEvent.exists?(event_key: "deliver-initiative-email:#{attempt.id}")).to be(false)
  end
end
