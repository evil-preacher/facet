module Privacy
  class RetentionJob < ApplicationJob
    queue_as :maintenance

    DIAGNOSTIC_TTL = 30.days
    ADMIN_AUDIT_TTL = 1.year

    def perform(now = Time.current)
      AdminAuditEvent.where("created_at < ?", now - ADMIN_AUDIT_TTL).delete_all
      cutoff = now - DIAGNOSTIC_TTL
      GenerationRun.where("created_at < ?", cutoff)
        .where.not(prompt_manifest: {}).update_all(prompt_manifest: {})
      GenerationRun.where("created_at < ?", cutoff).where.not(error_message: nil)
        .update_all(error_message: nil)
      ModelCall.where("created_at < ?", cutoff).where.not(error_message: nil)
        .update_all(error_message: nil)
      MemoryExtraction.where("created_at < ?", cutoff).where.not(error_message: nil)
        .update_all(error_message: nil)
      MessageImage.where("created_at < ?", cutoff).where.not(error_message: nil)
        .update_all(error_message: nil)
      Personality.where("updated_at < ?", cutoff).where.not(avatar_error_message: nil)
        .update_all(avatar_error_message: nil)
      OutboxEvent.where("created_at < ?", cutoff).where.not(last_error: nil)
        .update_all(last_error: nil)
    end
  end
end
