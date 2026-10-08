module ConversationThreads
  class ContextUpdates
    SUMMARY_MESSAGE_INTERVAL = 12
    RELATIONSHIP_CONSOLIDATION_INTERVAL = 25

    def self.prepare(generation_run:)
      return [] unless generation_run.completed? && generation_run.assistant_message&.completed?

      events = [
        Outbox::Publish.call(
          event_key: "relationship-update:#{generation_run.id}",
          job_class: Ai::RelationshipUpdateJob,
          arguments: [ generation_run.id ]
        )
      ]
      if generation_run.conversation_thread.personality.dynamic_state_enabled?
        events << Outbox::Publish.call(
          event_key: "dynamic-state-update:#{generation_run.id}",
          job_class: Ai::DynamicStateUpdateJob,
          arguments: [ generation_run.id ]
        )
      end
      if summary_due?(generation_run)
        events << Outbox::Publish.call(
          event_key: "thread-summary:#{generation_run.id}",
          job_class: Ai::ThreadSummaryJob,
          arguments: [ generation_run.id ]
        )
      end
      if relationship_consolidation_due?(generation_run)
        events << Outbox::Publish.call(
          event_key: "relationship-consolidation:#{generation_run.id}",
          job_class: Ai::RelationshipConsolidationJob,
          arguments: [ generation_run.id ]
        )
      end
      events
    end

    def self.summary_due?(generation_run)
      thread = generation_run.conversation_thread
      relation = thread.messages.completed.where("position <= ?", generation_run.assistant_message.position)
      relation = relation.where("position > ?", thread.summary_through_message.position) if thread.summary_through_message
      relation.count >= SUMMARY_MESSAGE_INTERVAL
    end
    private_class_method :summary_due?

    def self.relationship_consolidation_due?(generation_run)
      personality_id = generation_run.conversation_thread.personality_id
      completed_count = GenerationRun.joins(:conversation_thread)
        .where(conversation_threads: { personality_id: personality_id }, status: "completed").count
      completed_count.positive? && (completed_count % RELATIONSHIP_CONSOLIDATION_INTERVAL).zero?
    end
    private_class_method :relationship_consolidation_due?
  end
end
