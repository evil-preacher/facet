module Personalities
  module AvatarGeneration
    class Prepare
      Result = Data.define(:outbox_event)

      def self.call(personality:, personality_version:)
        outbox_event = nil

        personality.with_lock do
          next unless personality.current_version_id == personality_version.id
          next if personality.avatar_object_key.present? || personality.avatar_ready?
          next if personality.avatar_source_version_id == personality_version.id &&
                  (personality.avatar_pending? || personality.avatar_generating?)

          personality.update!(
            avatar_status: :pending,
            avatar_source_version: personality_version,
            avatar_started_at: nil,
            avatar_error_code: nil,
            avatar_error_message: nil
          )
          outbox_event = Outbox::Publish.call(
            event_key: "generate-avatar:#{personality.id}:#{personality_version.id}",
            job_class: Ai::GenerateAvatarJob,
            arguments: [ personality.id, personality_version.id ]
          )
        end

        Result.new(outbox_event: outbox_event)
      end
    end
  end
end
