require "diff/lcs"

module Personalities
  class VersionDiff
    Change = Data.define(:type, :old_number, :new_number, :old_line, :new_line)
    TYPES = {
      "=" => :unchanged,
      "!" => :changed,
      "-" => :removed,
      "+" => :added
    }.freeze

    attr_reader :from_version, :to_version, :changes

    def self.call(from_version:, to_version:)
      new(from_version: from_version, to_version: to_version)
    end

    def initialize(from_version:, to_version:)
      unless from_version.personality_id == to_version.personality_id
        raise ArgumentError, "versions must belong to the same personality"
      end

      @from_version = from_version
      @to_version = to_version
      @changes = build_changes.freeze
    end

    private

    def build_changes
      old_lines = from_version.content.lines(chomp: true)
      new_lines = to_version.content.lines(chomp: true)

      Diff::LCS.sdiff(old_lines, new_lines).map do |change|
        Change.new(
          type: TYPES.fetch(change.action),
          old_number: line_number(change.old_position, change.old_element),
          new_number: line_number(change.new_position, change.new_element),
          old_line: change.old_element,
          new_line: change.new_element
        )
      end
    end

    def line_number(position, element)
      position + 1 if element
    end
  end
end
