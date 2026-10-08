require "base64"

module DataExports
  class Build
    def self.call(user:, storage: ObjectStorage::S3Store.default)
      new(user, storage).call
    end

    def initialize(user, storage)
      @user = user
      @storage = storage
    end

    def call
      {
        exported_at: Time.current.iso8601,
        account: @user.slice(:id, :email, :created_at, :monthly_ai_limit_microusd),
        profile: @user.profile&.slice(:first_name, :last_name, :gender, :birth_date),
        personalities: @user.personalities.order(:id).map { |personality| export_personality(personality) },
        usage: @user.model_calls.order(:id).map do |call|
          call.slice(:id, :personality_id, :purpose, :provider, :model, :status,
                     :input_tokens, :cached_input_tokens, :output_tokens, :cost_microusd,
                     :created_at, :completed_at)
        end
      }
    end

    private

    def export_personality(personality)
      {
        details: personality.slice(:id, :name, :description, :status, :created_at,
                                   :initiative_enabled, :initiative_email_enabled,
                                   :initiative_idle_hours, :initiative_cooldown_hours,
                                   :initiative_intensity, :initiative_timezone,
                                   :initiative_quiet_start_hour, :initiative_quiet_end_hour,
                                   :dynamic_state_enabled),
        avatar: export_asset(personality.avatar_object_key, personality.avatar_content_type),
        versions: personality.versions.map do |version|
          version.slice(:id, :number, :content, :change_note, :created_at)
        end,
        memories: personality.memories.order(:id).map do |memory|
          memory.slice(:id, :kind, :content, :status, :origin, :sensitivity, :created_at, :deleted_at)
        end,
        relationship: personality.relationship_state&.slice(:summary, :revision, :trust, :closeness, :tension),
        emotional_state: personality.emotional_state&.slice(:warmth, :irritation, :observed_at),
        dynamic_observations: personality.dynamic_state_observations.order(:id).map do |observation|
          observation.slice(:generation_run_id, :extraction, :rules_version, :created_at)
        end,
        dynamic_revisions: personality.relationship_state&.dynamic_revisions&.map do |revision|
          revision.slice(:revision, :generation_run_id, :source_revision_id, :event_kind,
                         :extraction, :slow_state, :fast_state, :parameter_reasons,
                         :source_message_ids, :rules_version, :effective_at)
        end || [],
        initiative_attempts: personality.initiative_attempts.order(:id).map do |attempt|
          attempt.slice(:id, :conversation_thread_id, :source_message_id, :message_id,
                        :status, :decision, :decision_reason, :topic, :motivation, :intensity,
                        :dynamic_state_revision_id, :decided_at, :created_at, :completed_at).merge(
                          email_delivery: attempt.initiative_email_delivery&.slice(
                            :status, :email_message_id, :error_code, :claimed_at, :delivered_at
                          )
                        )
        end,
        threads: personality.conversation_threads.order(:id).map do |thread|
          {
            details: thread.slice(:id, :title, :status, :summary, :created_at),
            messages: thread.messages.order(:position).map do |message|
              message.slice(:id, :position, :role, :status, :content, :created_at, :read_at, :initiated_by,
                            :initiative_feedback, :initiative_feedback_at).merge(
                attachment: export_asset(message.attachment&.object_key, message.attachment&.content_type),
                generated_image: export_asset(message.message_image&.object_key, message.message_image&.content_type)
              )
            end
          }
        end
      }
    end

    def export_asset(key, content_type)
      return if key.blank?

      { content_type: content_type, data_base64: Base64.strict_encode64(@storage.download(key: key)) }
    end
  end
end
