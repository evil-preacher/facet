module Memories
  class Delete
    def self.call(memory:, user:, now: Time.current)
      raise ActiveRecord::RecordNotFound unless memory.personality.user_id == user.id

      memory.with_lock do
        return memory if memory.deleted?

        memory.update!(status: :deleted, deleted_at: now)
      end
      memory
    end
  end
end
