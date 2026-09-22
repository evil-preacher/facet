module Memories
  class ApplyCandidates
    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(extraction:, candidates:)
      @extraction = extraction
      @personality = extraction.personality
      @candidates = candidates
    end

    def call
      created = []
      personality.with_lock do
        candidates.each do |candidate|
          memory = apply_candidate(candidate)
          created << memory if memory
        end
      end
      created
    end

    private

    attr_reader :extraction, :personality, :candidates

    def apply_candidate(candidate)
      classification = SensitivityPolicy.classify(
        content: candidate.fetch("content"),
        model_sensitivity: candidate.fetch("sensitivity")
      )
      return if classification == :prohibited

      duplicate = current_duplicate(candidate)
      if duplicate
        attach_sources(duplicate, candidate.fetch("source_message_ids"))
        duplicate.update!(importance: [ duplicate.importance, candidate.fetch("importance") ].max)
        return
      end

      replaced = replaced_memory(candidate)
      status = if classification == :sensitive || candidate.fetch("action") == "contradiction"
        :pending
      else
        :active
      end
      memory = personality.memories.create!(
        kind: candidate.fetch("kind"),
        content: candidate.fetch("content"),
        importance: candidate.fetch("importance"),
        status: status,
        origin: :model,
        sensitivity: classification == :sensitive ? :sensitive : :normal,
        occurred_at: candidate.fetch("occurred_at"),
        supersedes: replaced
      )
      attach_sources(memory, candidate.fetch("source_message_ids"))
      replaced&.update!(status: :superseded) if memory.active?
      memory
    end

    def current_duplicate(candidate)
      personality.memories.current.find_by(
        kind: candidate.fetch("kind"),
        normalized_content: Memory.normalize(candidate.fetch("content"))
      )
    end

    def replaced_memory(candidate)
      return if candidate.fetch("action") == "create"

      personality.memories.active.find(candidate.fetch("existing_memory_id"))
    end

    def attach_sources(memory, message_ids)
      message_ids.each do |message_id|
        memory.memory_sources.create_or_find_by!(message_id: message_id)
      end
    end
  end
end
