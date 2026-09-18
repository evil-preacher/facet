require "rails_helper"

RSpec.describe "Concurrent personality versioning", :truncation do
  it "serializes version numbers and leaves the latest version current" do
    personality = create(:personality)
    first_version = create(
      :personality_version,
      personality: personality,
      number: 1,
      content: "# Original"
    )
    personality.update!(current_version: first_version, status: :active)

    ready = Queue.new
    start = Queue.new
    results = Queue.new

    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          local_personality = Personality.find(personality.id)
          ready << true
          start.pop
          results << Personalities::Update.call(
            personality: local_personality,
            author: local_personality.user,
            attributes: {
              name: local_personality.name,
              description: local_personality.description,
              character_bible: "# Concurrent #{index}",
              change_note: "Concurrent save #{index}"
            }
          )
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)

    outcomes = 2.times.map { results.pop }
    personality.reload

    expect(outcomes).to all(be_success)
    expect(personality.versions.order(:number).pluck(:number)).to eq([ 1, 2, 3 ])
    expect(personality.current_version.number).to eq(3)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end
end
