module Personalities
  class CharacterBibleSections
    class << self
      def extract(content, names:)
        requested_names = names.index_by { |name| normalize(name) }
        sections = Hash.new { |hash, key| hash[key] = [] }
        current_section = nil

        normalize_newlines(content).each_line(chomp: true) do |line|
          heading = h1_heading(line)
          if heading
            normalized_heading = normalize(heading)
            current_section = requested_names.key?(normalized_heading) ? normalized_heading : nil
            next
          end

          sections[current_section] << line if current_section
        end

        requested_names.filter_map do |normalized_name, display_name|
          body = sections[normalized_name].join("\n").strip
          next if body.blank?

          "# #{display_name}\n\n#{body}"
        end.join("\n\n")
      end

      private

      def normalize_newlines(content)
        content.to_s.gsub("\r\n", "\n").gsub("\r", "\n")
      end

      def h1_heading(line)
        match = line.match(/\A#(?!#)\s+(.+?)\s*\z/)
        match && match[1].sub(/\s+#+\s*\z/, "")
      end

      def normalize(name)
        name.to_s.downcase.gsub(/\s+/, " ").strip
      end
    end
  end
end
