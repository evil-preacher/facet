module Ai
  class TokenCounter
    def count(text)
      text.to_s.each_char.count
    end

    def truncate(text, max_tokens, from: :start)
      characters = text.to_s.each_char.to_a
      limit = [ Integer(max_tokens), 0 ].max
      return characters.first(limit).join if from == :start
      return characters.last(limit).join if from == :end

      raise ArgumentError, "Unknown truncation direction: #{from}"
    end
  end
end
