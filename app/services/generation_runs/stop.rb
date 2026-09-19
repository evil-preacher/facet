module GenerationRuns
  class Stop
    include ActiveModel::Model

    attr_reader :generation_run

    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(generation_run:, now: Time.current)
      @generation_run = generation_run
      @now = now
    end

    def call
      generation_run.with_lock do
        unless generation_run.pending? || generation_run.running?
          errors.add(:generation_run, :invalid)
          return self
        end

        generation_run.assistant_message&.update!(status: :stopped)
        generation_run.update!(status: :stopped, completed_at: @now)
      end
      self
    end

    def success?
      errors.empty? && generation_run.stopped?
    end
  end
end
