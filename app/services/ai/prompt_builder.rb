require "base64"

module Ai
  class PromptBuilder
    InputItem = Data.define(:role, :content)
    Result = Data.define(:input, :manifest, :prompt_cache_key, :estimated_tokens)
    IMAGE_TOKEN_ESTIMATE = 1_024

    APPLICATION_RULES = <<~RULES.strip.freeze
      [Prompt text removed from public history]
    RULES

    DEFAULT_BUDGETS = {
      application_rules: 2_000,
      character_bible: 52_000,
      relationship_state: 2_000,
      memories: 4_000,
      thread_summary: 4_000,
      recent_messages: 8_000,
      current_message: 12_000,
      total: 100_000
    }.freeze

    SECTION_ORDER = %w[
      application_rules
      character_bible
      relationship_state
      memories
      thread_summary
      recent_messages
      current_message
    ].freeze

    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(generation_run:, relationship_state: nil, memories: [],
                   token_counter: TokenCounter.new, budgets: {},
                   storage: ObjectStorage::S3Store.default)
      @generation_run = generation_run
      @thread = generation_run.conversation_thread
      @personality = @thread.personality
      @personality_version = generation_run.personality_version
      @current_message = generation_run.user_message
      @relationship_state = owned_relationship(relationship_state)
      @memories = owned_memories(memories)
      @token_counter = token_counter
      @storage = storage
      @budgets = DEFAULT_BUDGETS.merge(budgets.to_h.symbolize_keys)
      validate_context!
    end

    def call
      prepare_sections
      enforce_total_budget
      manifest = build_manifest
      @generation_run.update!(prompt_manifest: manifest)

      Result.new(
        input: assembled_input.freeze,
        manifest: manifest.deep_dup.freeze,
        prompt_cache_key: prompt_cache_key,
        estimated_tokens: total_tokens
      )
    end

    private

    def validate_context!
      valid = @current_message.user? &&
        @current_message.conversation_thread_id == @thread.id &&
        @personality_version.personality_id == @personality.id &&
        @current_message.personality_version_id == @personality_version.id
      raise ArgumentError, "Generation run prompt context is inconsistent" unless valid
    end

    def owned_relationship(relationship_state)
      return unless relationship_state&.personality_id == @personality.id

      relationship_state
    end

    def owned_memories(memories)
      Array(memories).select { |memory| memory.personality_id == @personality.id }
    end

    def prepare_sections
      @rules_item = developer_item("Application rules", APPLICATION_RULES)
      @bible_item = developer_item(
        "Character bible",
        wrap_section("character_bible", @personality_version.content)
      )
      prepare_relationship
      prepare_memories
      prepare_summary
      prepare_history
      @current_item = current_message_item
      @detected_language = LanguageDetector.call(@current_message.content)
    end

    def prepare_relationship
      @relationship_truncated = false
      return @relationship_item = nil unless @relationship_state

      @relationship_item, @relationship_truncated = budgeted_context_item(
        "Relationship state",
        "relationship_state",
        @relationship_state.summary,
        section_budget(:relationship_state)
      )
    end

    def prepare_memories
      @selected_memories = []
      @memories.each do |memory|
        candidate = @selected_memories + [ memory ]
        candidate_item = memory_item(candidate)
        break if count(candidate_item.content) > section_budget(:memories)

        @selected_memories = candidate
      end
      @memories_truncated = @selected_memories.length < @memories.length
      rebuild_memory_item
    end

    def prepare_summary
      @summary_truncated = false
      return @summary_item = nil if @thread.summary.blank?

      @summary_item, @summary_truncated = budgeted_context_item(
        "Thread summary",
        "thread_summary",
        @thread.summary,
        section_budget(:thread_summary)
      )
    end

    def prepare_history
      messages = @thread.messages.completed
        .where.not(id: @current_message.id)
        .where("position < ?", @current_message.position)
        .reorder(position: :desc)
      remaining = section_budget(:recent_messages)
      selected = []

      messages.each do |message|
        tokens = count(message.content)
        break if tokens > remaining

        selected << message
        remaining -= tokens
      end

      @history_messages = selected.reverse
      @history_truncated = @history_messages.length < messages.length
      rebuild_history_items
    end

    def enforce_total_budget
      while total_tokens > section_budget(:total) && @history_messages.any?
        @history_messages.shift
        @history_truncated = true
        rebuild_history_items
      end

      while total_tokens > section_budget(:total) && @selected_memories.any?
        @selected_memories.pop
        @memories_truncated = true
        rebuild_memory_item
      end

      drop_optional_item(:summary)
      drop_optional_item(:relationship)
    end

    def drop_optional_item(name)
      item_variable = "@#{name}_item"
      item = instance_variable_get(item_variable)
      return unless total_tokens > section_budget(:total) && item

      instance_variable_set(item_variable, nil)
      instance_variable_set("@#{name}_truncated", true)
    end

    def rebuild_memory_item
      @memory_item = memory_item(@selected_memories) if @selected_memories.any?
    end

    def memory_item(memories)
      developer_item("Relevant memories", wrap_section("memories", memory_content(memories)))
    end

    def rebuild_history_items
      @history_items = @history_messages.map do |message|
        InputItem.new(role: message.role, content: message.content)
      end
    end

    def current_message_item
      attachment = @current_message.attachment
      text = @current_message.content.presence || "[Prompt text removed from public history]"
      return InputItem.new(role: "user", content: text) unless attachment

      bytes = @storage.download(key: attachment.object_key)
      data_url = "data:#{attachment.content_type};base64,#{Base64.strict_encode64(bytes)}"
      InputItem.new(
        role: "user",
        content: [
          { type: "text", text: text },
          {
            type: "image_url",
            image_url: { url: data_url }
          }
        ]
      )
    end

    def assembled_input
      [
        @rules_item,
        @bible_item,
        @relationship_item,
        @memory_item,
        @summary_item,
        *@history_items,
        @current_item
      ].compact
    end

    def memory_content(memories)
      memories.map { |memory| "- [memory #{memory.id}] #{memory.content}" }.join("\n")
    end

    def developer_item(title, content)
      InputItem.new(role: "developer", content: "## #{title}\n#{content}")
    end

    def wrap_section(name, content)
      "<#{name}>\n#{content}\n</#{name}>"
    end

    def budgeted_context_item(title, name, content, budget)
      empty_item = developer_item(title, wrap_section(name, ""))
      available = budget - count(empty_item.content)
      return [ nil, true ] if available <= 0

      truncated_content = @token_counter.truncate(content, available)
      item = developer_item(title, wrap_section(name, truncated_content))
      [ item, truncated_content != content ]
    end

    def prompt_cache_key
      "facet-conversation-pv-#{@personality_version.id}-v3"
    end

    def total_tokens
      assembled_input.sum { |item| count(item.content) }
    end

    def count(content)
      return @token_counter.count(content) unless content.is_a?(Array)

      content.sum do |part|
        case part[:type].to_s
        when "text"
          @token_counter.count(part[:text].to_s)
        when "image_url"
          IMAGE_TOKEN_ESTIMATE
        else
          0
        end
      end
    end

    def section_budget(name)
      Integer(@budgets.fetch(name))
    end

    def build_manifest
      {
        "schema_version" => 1,
        "personality_id" => @personality.id,
        "personality_version_id" => @personality_version.id,
        "conversation_thread_id" => @thread.id,
        "current_message_id" => @current_message.id,
        "relationship_state_id" => @relationship_state&.id,
        "relationship_revision" => @relationship_state&.revision,
        "memory_ids" => @selected_memories.map(&:id),
        "summary_through_message_id" => @thread.summary_through_message_id,
        "recent_message_ids" => @history_messages.map(&:id),
        "detected_language" => @detected_language,
        "prompt_cache_key" => prompt_cache_key,
        "total_budget" => section_budget(:total),
        "total_estimated_tokens" => total_tokens,
        "protected_over_budget" => total_tokens > section_budget(:total),
        "sections" => section_manifests
      }
    end

    def section_manifests
      items = {
        "application_rules" => [ @rules_item ],
        "character_bible" => [ @bible_item ],
        "relationship_state" => [ @relationship_item ],
        "memories" => [ @memory_item ],
        "thread_summary" => [ @summary_item ],
        "recent_messages" => @history_items,
        "current_message" => [ @current_item ]
      }
      truncated = {
        "relationship_state" => @relationship_truncated,
        "memories" => @memories_truncated,
        "thread_summary" => @summary_truncated,
        "recent_messages" => @history_truncated
      }

      SECTION_ORDER.map do |name|
        section_items = items.fetch(name).compact
        estimated_tokens = section_items.sum { |item| count(item.content) }
        budget = section_budget(name.to_sym)
        {
          "name" => name,
          "budget" => budget,
          "estimated_tokens" => estimated_tokens,
          "item_count" => section_items.length,
          "truncated" => truncated.fetch(name, false),
          "over_budget" => estimated_tokens > budget
        }
      end
    end
  end
end
