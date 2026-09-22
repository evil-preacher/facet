module Relationships
  class Rollback
    def self.call(relationship_state:, source_version:)
      unless source_version.relationship_state_id == relationship_state.id
        raise ArgumentError, "Relationship version belongs to another state"
      end

      relationship_state.with_lock do
        revision = relationship_state.revision + 1
        version = relationship_state.versions.create!(
          source_version: source_version,
          revision: revision,
          summary: source_version.summary,
          source_message_ids: [],
          reason: :rollback
        )
        relationship_state.update!(summary: version.summary, revision: revision)
        version
      end
    end
  end
end
