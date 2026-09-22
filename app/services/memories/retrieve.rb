module Memories
  class Retrieve
    Result = Data.define(:memories, :diagnostics)
    DEFAULT_LIMIT = 12
    DEFAULT_TOKEN_BUDGET = 4_000

    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(personality:, query:, limit: DEFAULT_LIMIT, token_budget: DEFAULT_TOKEN_BUDGET,
                   token_counter: Ai::TokenCounter.new, now: Time.current)
      @personality = personality
      @query = query.to_s.squish
      @limit = Integer(limit)
      @token_budget = Integer(token_budget)
      @token_counter = token_counter
      @now = now
    end

    def call
      selected = []
      used_tokens = 0
      diagnostics = []

      ranked_memories.each do |memory|
        tokens = token_counter.count("- [memory #{memory.id}] #{memory.content}")
        next if used_tokens + tokens > token_budget

        selected << memory
        used_tokens += tokens
        diagnostics << diagnostic(memory, tokens, selected.length)
        break if selected.length >= limit
      end

      Result.new(memories: selected.freeze, diagnostics: diagnostics.freeze)
    end

    private

    attr_reader :personality, :query, :limit, :token_budget, :token_counter, :now

    def ranked_memories
      relation = personality.memories.available_for_retrieval
      relation = relation.select("memories.*", "#{text_rank_sql} AS retrieval_text_rank", "#{score_sql} AS retrieval_score")
      relation.order(Arel.sql("retrieval_score DESC, memories.id ASC")).limit([ limit * 5, 100 ].min)
    end

    def text_rank_sql
      return "0.0" if query.blank?

      terms = query.downcase.scan(/[[:alnum:]]{2,}/).uniq.first(12)
      return "0.0" if terms.empty?

      quoted_query = ActiveRecord::Base.connection.quote(terms.join(" | "))
      "ts_rank_cd(to_tsvector('simple', coalesce(memories.content, '')), " \
        "to_tsquery('simple', #{quoted_query}))"
    end

    def score_sql
      recent_30 = ActiveRecord::Base.connection.quote(now - 30.days)
      recent_180 = ActiveRecord::Base.connection.quote(now - 180.days)
      <<~SQL.squish
        ((#{text_rank_sql}) * 100.0) +
        (memories.importance / 10.0) +
        CASE
          WHEN COALESCE(memories.occurred_at, memories.updated_at) >= #{recent_30} THEN 3.0
          WHEN COALESCE(memories.occurred_at, memories.updated_at) >= #{recent_180} THEN 1.5
          ELSE 0.0
        END +
        CASE memories.kind
          WHEN 'boundary' THEN 2.0
          WHEN 'relationship' THEN 1.5
          WHEN 'preference' THEN 1.0
          ELSE 0.0
        END
      SQL
    end

    def diagnostic(memory, tokens, rank)
      text_rank = memory.attributes.fetch("retrieval_text_rank", 0).to_f
      {
        "memory_id" => memory.id,
        "rank" => rank,
        "score" => memory.attributes.fetch("retrieval_score").to_f.round(4),
        "token_count" => tokens,
        "reasons" => {
          "text_relevance" => text_rank.round(4),
          "importance" => memory.importance,
          "kind" => memory.kind,
          "occurred_at" => memory.occurred_at&.iso8601,
          "last_recalled_at" => memory.last_recalled_at&.iso8601
        }
      }
    end
  end
end
