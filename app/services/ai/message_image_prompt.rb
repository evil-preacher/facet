module Ai
  class MessageImagePrompt
    def self.call(message_image:)
      new(message_image: message_image).call
    end

    def initialize(message_image:)
      @message_image = message_image
      @personality = message_image.message.conversation_thread.personality
    end

    def call
      <<~PROMPT.strip
      [Prompt text removed from public history]
      PROMPT
    end

    private

    attr_reader :message_image, :personality
  end
end
