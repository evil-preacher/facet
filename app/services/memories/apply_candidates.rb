module Memories
  class ApplyCandidates
    MIN_IMPORTANCE = 50
    CORRECTION_PHRASES = [
      "actually", "now", "no longer", "used to",
      "на самом деле", "теперь", "больше не", "раньше", "ошиб", "исправ"
    ].freeze
    CONTENT_STOP_WORDS = %w[
      пользователь пользователю пользователя пользовательница
      сказал сказала говорит выразил выразила считает использовал использовала
      фраза фразу свой свою что этот эта это эти как или при для про
      the user said says expressed thinks used phrase that this with from
    ].freeze
    KIND_PRIORITY = {
      "boundary" => 4,
      "preference" => 3,
      "fact" => 2,
      "other" => 1
    }.freeze

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
        compacted_candidates.each do |candidate|
          memory = apply_candidate(candidate)
          created << memory if memory
        end
      end
      created
    end

    private

    attr_reader :extraction, :personality, :candidates

    def compacted_candidates
      candidates
        .select { |candidate| candidate.fetch("importance") >= MIN_IMPORTANCE }
        .sort_by { |candidate| candidate_rank(candidate) }
        .reverse
        .each_with_object([]) do |candidate, kept|
          kept << candidate unless kept.any? { |other| batch_duplicate?(candidate, other) }
        end
    end

    def candidate_rank(candidate)
      [ candidate.fetch("importance"), KIND_PRIORITY.fetch(candidate.fetch("kind"), 0),
        content_tokens(candidate.fetch("content")).length ]
    end

    def batch_duplicate?(candidate, other)
      return false unless candidate.fetch("source_message_ids").sort == other.fetch("source_message_ids").sort

      candidate_tokens = content_tokens(candidate.fetch("content"))
      other_tokens = content_tokens(other.fetch("content"))
      overlap = (candidate_tokens & other_tokens).length
      shorter_size = [ candidate_tokens.length, other_tokens.length ].min
      return false if shorter_size.zero?

      overlap.fdiv(shorter_size) >= 0.6 || quote_duplicate?(candidate, other, overlap)
    end

    def quote_duplicate?(candidate, other, overlap)
      return false unless [ candidate.fetch("kind"), other.fetch("kind") ].include?("other")

      overlap >= 2
    end

    def content_tokens(content)
      content.downcase.scan(/[[:alpha:][:digit:]]+/)
        .reject { |token| token.length < 4 || CONTENT_STOP_WORDS.include?(token) }
        .map { |token| token[0, 6] }
        .uniq
    end

    def apply_candidate(candidate)
      classification = SensitivityPolicy.classify(
        content: candidate.fetch("content"),
        model_sensitivity: candidate.fetch("sensitivity")
      )
      return if classification == :prohibited

      duplicate = current_duplicate(candidate) || semantic_duplicate(candidate)
      if duplicate
        attach_sources(duplicate, candidate.fetch("source_message_ids"))
        duplicate.update!(
          importance: [ duplicate.importance, candidate.fetch("importance") ].max,
          sensitivity: classification == :sensitive ? :sensitive : duplicate.sensitivity
        )
        return
      end

      replaced = replaced_memory(candidate)
      status = if candidate.fetch("action") == "contradiction"
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

    def semantic_duplicate(candidate)
      return unless candidate.fetch("action") == "create"

      candidate_content = candidate.fetch("content")
      candidate_tokens = content_tokens(candidate_content)
      return if candidate_tokens.length < 3

      personality.memories.current.where(kind: candidate.fetch("kind")).find_each.find do |memory|
        next false unless negative?(candidate_content) == negative?(memory.content)

        existing_tokens = content_tokens(memory.content)
        next false if existing_tokens.length < 3

        overlap = (candidate_tokens & existing_tokens).length
        overlap >= 3 && overlap.fdiv([ candidate_tokens.length, existing_tokens.length ].min) >= 0.75
      end
    end

    def negative?(content)
      content.downcase.scan(/[[:alpha:]]+/).any? { |word| %w[не нет без not no never].include?(word) }
    end

    def replaced_memory(candidate)
      return if candidate.fetch("action") == "create"

      memory = personality.memories.active.find(candidate.fetch("existing_memory_id"))
      return unless memory.kind == candidate.fetch("kind")

      return memory if candidate.fetch("action") == "contradiction"

      memory if explicit_correction?(candidate.fetch("source_message_ids"))
    end

    def explicit_correction?(message_ids)
      text = Message.where(id: message_ids).pluck(:content).join(" ").downcase
      CORRECTION_PHRASES.any? { |phrase| text.include?(phrase) }
    end

    def attach_sources(memory, message_ids)
      message_ids.each do |message_id|
        memory.memory_sources.create_or_find_by!(message_id: message_id)
      end
    end
  end
end
