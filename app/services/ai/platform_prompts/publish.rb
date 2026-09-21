module Ai
  module PlatformPrompts
    class Publish
      def self.call(provider:, purpose: "conversation", content:)
        new(provider: provider, purpose: purpose, content: content).call
      end

      def initialize(provider:, purpose:, content:)
        @provider = provider.to_s.strip.downcase
        @purpose = purpose.to_s.strip.downcase
        @content = content.to_s.strip
      end

      def call
        AiPlatformPrompt.transaction do
          active = AiPlatformPrompt.active
            .lock
            .find_by(provider: provider, purpose: purpose)
          return active if active&.content == content

          active&.update!(status: :retired)
          revision = AiPlatformPrompt.where(provider: provider, purpose: purpose).maximum(:revision).to_i + 1
          AiPlatformPrompt.create!(
            provider: provider,
            purpose: purpose,
            revision: revision,
            content: content,
            status: :active,
            published_at: Time.current
          )
        end
      end

      private

      attr_reader :provider, :purpose, :content
    end
  end
end
