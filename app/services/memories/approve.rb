module Memories
  class Approve
    def self.call(memory:, user:)
      raise ActiveRecord::RecordNotFound unless memory.personality.user_id == user.id

      Memory.transaction do
        memory.lock!
        return memory unless memory.pending?

        replaced = memory.supersedes
        replaced&.lock!
        replaced&.update!(status: :superseded) if replaced.active?
        memory.update!(status: :active)
      end
      memory
    end
  end
end
