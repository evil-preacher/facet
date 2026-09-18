module ConversationThreads
  class Archive
    def self.call(conversation_thread:)
      new(conversation_thread).call
    end

    def initialize(conversation_thread)
      @conversation_thread = conversation_thread
    end

    def call
      @conversation_thread.update!(status: :archived)
      @conversation_thread
    end
  end
end
