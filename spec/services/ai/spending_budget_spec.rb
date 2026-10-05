require "rails_helper"

RSpec.describe Ai::SpendingBudget do
  let(:now) { Time.zone.parse("2026-10-05 12:00:00") }
  let(:user) { create(:user, monthly_ai_limit_microusd: 70_000) }
  let(:personality) { create(:personality, user: user) }
  let(:price) { create(:model_price) }

  def reserve(at: now, owner: user, character: personality)
    described_class.reserve!(user: owner, personality: character, generation_run: nil,
                             purpose: :conversation, provider: price.provider, model: price.model,
                             price: price, input: "hello", response_schema: nil,
                             max_output_tokens: 4_096, now: at)
  end

  it "counts active reservations and releases capacity when a call settles" do
    first = reserve
    expect(first.reserved_cost_microusd).to be > 40_000
    expect(described_class.snapshot(user: user, now: now).reserved).to eq(first.reserved_cost_microusd)
    expect { reserve }.to raise_error(Ai::BudgetExceededError)

    first.update!(status: :completed, input_tokens: 5, cached_input_tokens: 0,
                  output_tokens: 1, cost_microusd: 23, pricing_version: price.version,
                  completed_at: now, reserved_cost_microusd: 0, reservation_expires_at: nil)
    expect { reserve }.not_to raise_error
  end

  it "warns when spending and reservations reach eighty percent" do
    owner = create(:user, monthly_ai_limit_microusd: 50_000)
    create(:model_call, user: owner, reserved_cost_microusd: 40_000,
           reservation_expires_at: now + 1.hour, created_at: now)

    expect(described_class.snapshot(user: owner, now: now)).to be_warning
  end

  it "starts a fresh budget at the next calendar month" do
    user.update!(monthly_ai_limit_microusd: 50_000)
    reserve(at: now)
    expect { reserve(at: now + 1.day) }.to raise_error(Ai::BudgetExceededError)
    expect { reserve(at: now.next_month) }.not_to raise_error
  end

  it "enforces the global limit across users" do
    allow(described_class).to receive(:global_limit).and_return(50_000)
    reserve
    other = create(:user)
    expect do
      reserve(owner: other, character: create(:personality, user: other))
    end.to raise_error(Ai::BudgetExceededError)
  end

  it "uses the configured application time zone for monthly boundaries" do
    Time.use_zone("Asia/Almaty") do
      instant = Time.utc(2026, 9, 30, 19, 0)
      range = described_class.month_range(instant)
      expect(range.begin.month).to eq(10)
      expect(range.end.month).to eq(11)
    end
  end

  it "serializes simultaneous reservations for the same remaining balance", :truncation do
    owner = user
    character = personality
    tariff = price
    owner.update!(monthly_ai_limit_microusd: 50_000)
    results = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            described_class.reserve!(user: owner, personality: character, generation_run: nil,
                                     purpose: :conversation, provider: tariff.provider, model: tariff.model,
                                     price: tariff, input: "hello", response_schema: nil,
                                     max_output_tokens: 4_096, now: now)
            results << :reserved
          rescue Ai::BudgetExceededError
            results << :blocked
          end
        end
      end
    end
    threads.each(&:join)
    expect(2.times.map { results.pop }.sort).to eq(%i[blocked reserved])
    expect(ModelCall.count).to eq(1)
  end
end
