module Ai
  class MessageImagePrompt
    SECTION_NAMES = [ "Identity", "Base character" ].freeze

    def self.call(message_image:)
      new(message_image: message_image).call
    end

    def initialize(message_image:)
      @message_image = message_image
      @message = message_image.message
      @thread = @message.conversation_thread
      @personality = @thread.personality
    end

    def call
      <<~PROMPT.strip
      [Prompt text removed from public history]
      PROMPT
    end

    private

    attr_reader :message_image, :message, :thread, :personality

    def character_context
      Personalities::CharacterBibleSections.extract(
        message.personality_version.content,
        names: SECTION_NAMES
      ).presence || "# Identity\n\nName: #{personality.name}"
    end
  end
end
