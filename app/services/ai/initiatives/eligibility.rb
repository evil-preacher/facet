module Ai
  module Initiatives
    class Eligibility
      Result = Data.define(:eligible, :thread, :last_user_message)

      def self.call(personality:, now: Time.current, except_attempt: nil, check_budget: true)
        new(personality: personality, now: now, except_attempt: except_attempt,
            check_budget: check_budget).call
      end

      def initialize(personality:, now:, except_attempt:, check_budget:)
        @personality = personality
        @now = now
        @except_attempt = except_attempt
        @check_budget = check_budget
      end

      def call
        return ineligible unless personality.active? && personality.initiative_enabled?

        message = Message.joins(:conversation_thread)
          .where(role: "user", conversation_threads: { personality_id: personality.id, status: "active" })
          .order(created_at: :desc, id: :desc).first
        return ineligible unless message
        return ineligible if message.created_at > now - personality.initiative_idle_hours.hours
        latest_activity = Message.joins(:conversation_thread)
          .where(conversation_threads: { personality_id: personality.id }).maximum(:created_at)
        return ineligible if latest_activity && latest_activity > now - personality.initiative_idle_hours.hours
        attempts = personality.initiative_attempts.where("created_at > ?", now - personality.initiative_cooldown_hours.hours)
        attempts = attempts.where.not(id: @except_attempt.id) if @except_attempt
        return ineligible if attempts.where(decision_reason: "quiet_hours")
          .where("created_at > ?", now - 1.hour).exists?
        attempts = attempts.where("decision_reason IS NULL OR decision_reason <> ?", "quiet_hours")
        return ineligible if attempts.exists?
        return ineligible if Message.unread_initiatives.joins(:conversation_thread)
          .where(conversation_threads: { personality_id: personality.id }).exists?
        return ineligible if GenerationRun.joins(:conversation_thread)
          .where(status: %w[pending running], conversation_threads: { personality_id: personality.id }).exists?
        return ineligible if @check_budget && SpendingBudget.snapshot(user: personality.user, now: now).remaining.zero?

        Result.new(eligible: true, thread: message.conversation_thread, last_user_message: message)
      end

      private

      attr_reader :personality, :now

      def ineligible
        Result.new(eligible: false, thread: nil, last_user_message: nil)
      end
    end
  end
end
