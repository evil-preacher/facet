module Ai
  module Initiatives
    class EmailDelivery
      Result = Data.define(:status, :error_code)

      def self.call(delivery:, now: Time.current)
        new(delivery: delivery, now: now).call
      end

      def initialize(delivery:, now:)
        @delivery = delivery
        @now = now
      end

      def call
        return result unless claim!

        personality.with_lock do
          block = Policy.email_delivery_block(personality: personality, now: now)
          return suppress!(block) if block

          UserMailer.with(
            personality: personality, message: attempt.message,
            email_message_id: delivery.email_message_id,
            locale: attempt.message.language.presence_in(%w[ru en]) || I18n.default_locale
          ).initiative_email.deliver_now
          delivery.update!(status: :delivered, delivered_at: now)
        end
        result
      rescue StandardError => error
        if delivery.sending?
          delivery.update!(status: :unknown, error_code: "delivery_result_unknown")
        elsif delivery.pending?
          delivery.update!(status: :failed, error_code: "delivery_preparation_failed")
        end
        Rails.logger.warn("Initiative email delivery failed id=#{delivery.id} error=#{error.class.name}")
        result
      end

      private

      attr_reader :delivery, :now

      def attempt = delivery.initiative_attempt
      def personality = attempt.personality

      def claim!
        delivery.with_lock do
          return false unless delivery.pending?
          unless attempt.completed? && attempt.decision == "EMAIL" && attempt.message
            suppress!("invalid_attempt")
            return false
          end

          personality.with_lock do
            block = Policy.email_delivery_block(personality: personality, now: now)
            if block
              suppress!(block)
              return false
            end

            delivery.update!(status: :sending, claimed_at: now, email_message_id: stable_message_id)
          end
        end
        true
      end

      def stable_message_id
        domain = ENV.fetch("MAILER_FROM", "no-reply@facet.local").split("@").last
        "<facet-initiative-#{attempt.id}@#{domain}>"
      end

      def suppress!(code)
        delivery.update!(status: :suppressed, error_code: code)
        result
      end

      def result
        Result.new(status: delivery.status.to_sym, error_code: delivery.error_code)
      end
    end
  end
end
