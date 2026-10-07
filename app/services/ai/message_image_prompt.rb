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
      Ai::PromptCatalog.render("message_image", character_name: personality.name, photo_specification: message_image.scene_description)
    end

    private

    attr_reader :message_image, :personality
  end
end
