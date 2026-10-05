module Operations
  class Diagnostics
    PENDING_RUN_AGE = 5.minutes
    RUNNING_RUN_AGE = 15.minutes
    MEMORY_AGE = 15.minutes
    INITIATIVE_AGE = 1.hour
    LIMIT = 50

    def self.call(now: Time.current)
      {
        pending_runs: GenerationRun.pending.where(created_at: ...now - PENDING_RUN_AGE)
          .order(:created_at).limit(LIMIT).pluck(:id, :created_at).map { |id, at| { id: id, since: at } },
        running_runs: GenerationRun.running.where(started_at: ...now - RUNNING_RUN_AGE)
          .order(:started_at).limit(LIMIT).pluck(:id, :started_at).map { |id, at| { id: id, since: at } },
        running_memory_extractions: MemoryExtraction.running.where(started_at: ...now - MEMORY_AGE)
          .order(:started_at).limit(LIMIT).pluck(:id, :started_at).map { |id, at| { id: id, since: at } },
        running_initiatives: InitiativeAttempt.running.where(started_at: ...now - INITIATIVE_AGE)
          .order(:started_at).limit(LIMIT).pluck(:id, :started_at).map { |id, at| { id: id, since: at } },
        pending_outbox: OutboxEvent.pending.where(created_at: ...now - PENDING_RUN_AGE)
          .order(:created_at).limit(LIMIT).pluck(:id, :created_at).map { |id, at| { id: id, since: at } }
      }
    end

    def self.retry_pending_run!(id:, now: Time.current)
      run = GenerationRun.pending.find(id)
      raise ActiveRecord::RecordNotFound if run.created_at > now - PENDING_RUN_AGE

      Ai::GenerateReplyJob.perform_later(run.id)
    end
  end
end
