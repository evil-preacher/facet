module Notifications
  class UnreadThreads
    Entry = Data.define(:thread, :personality, :count, :last_message)

    def self.scope_for(user)
      Message.unread_initiatives.joins(conversation_thread: :personality)
        .where(personalities: { user_id: user.id })
    end

    def self.count_for(user)
      scope_for(user).distinct.count(:conversation_thread_id)
    end

    def self.call(user:)
      scope_for(user).includes(conversation_thread: :personality)
        .order(created_at: :desc, id: :desc).to_a
        .group_by(&:conversation_thread_id)
        .map do |_thread_id, messages|
          thread = messages.first.conversation_thread
          Entry.new(thread: thread, personality: thread.personality,
                    count: messages.length, last_message: messages.first)
        end
        .sort_by { |entry| [ -entry.last_message.created_at.to_f, -entry.last_message.id ] }
    end
  end
end
