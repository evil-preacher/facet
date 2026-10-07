# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_07_000003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "admin_audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_user_id", null: false
    t.datetime "created_at", null: false
    t.bigint "target_id"
    t.string "target_type", null: false
    t.index ["actor_user_id", "created_at"], name: "index_admin_audit_events_on_actor_user_id_and_created_at"
    t.index ["target_type", "target_id", "created_at"], name: "idx_on_target_type_target_id_created_at_6d5232a721"
    t.check_constraint "action::text = ANY (ARRAY['index'::character varying, 'show'::character varying, 'disable_initiative'::character varying, 'retry_pending'::character varying, 'publish_prompt'::character varying, 'publish_platform_prompt'::character varying]::text[])", name: "admin_audit_events_action"
  end

  create_table "ai_budget_locks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ai_platform_prompts", force: :cascade do |t|
    t.string "checksum", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.datetime "published_at"
    t.string "purpose", default: "conversation", null: false
    t.integer "revision", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "purpose", "revision"], name: "index_ai_platform_prompts_on_provider_and_purpose_and_revision", unique: true
    t.index ["provider", "purpose"], name: "index_ai_platform_prompts_on_active_scope", unique: true, where: "((status)::text = 'active'::text)"
    t.check_constraint "char_length(btrim(content)) >= 1 AND char_length(btrim(content)) <= 20000", name: "ai_platform_prompts_content_length"
    t.check_constraint "provider::text = ANY (ARRAY['mistral'::character varying, 'openai'::character varying]::text[])", name: "ai_platform_prompts_provider"
    t.check_constraint "purpose::text = 'conversation'::text", name: "ai_platform_prompts_purpose"
    t.check_constraint "revision > 0", name: "ai_platform_prompts_positive_revision"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'retired'::character varying]::text[])", name: "ai_platform_prompts_status"
  end

  create_table "ai_prompt_revisions", force: :cascade do |t|
    t.string "checksum", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.bigint "published_by_id"
    t.integer "revision", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["key", "revision"], name: "index_ai_prompt_revisions_on_key_and_revision", unique: true
    t.index ["key"], name: "index_ai_prompt_revisions_active_key", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["published_by_id"], name: "index_ai_prompt_revisions_on_published_by_id"
    t.check_constraint "char_length(btrim(content)) >= 1 AND char_length(btrim(content)) <= 100000", name: "ai_prompt_revisions_content_length"
    t.check_constraint "revision > 0", name: "ai_prompt_revisions_positive_revision"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'retired'::character varying]::text[])", name: "ai_prompt_revisions_status"
  end

  create_table "conversation_threads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_message_at"
    t.bigint "personality_id", null: false
    t.string "status", default: "active", null: false
    t.text "summary"
    t.bigint "summary_through_message_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["personality_id", "status", "last_message_at"], name: "idx_on_personality_id_status_last_message_at_8f99ecdef1"
    t.index ["personality_id"], name: "index_conversation_threads_on_personality_id"
    t.index ["summary_through_message_id"], name: "index_conversation_threads_on_summary_through_message_id"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'archived'::character varying]::text[])", name: "conversation_threads_status"
    t.check_constraint "summary IS NULL OR char_length(summary) <= 100000", name: "conversation_threads_summary_length"
    t.check_constraint "title IS NULL OR char_length(btrim(title::text)) >= 1 AND char_length(btrim(title::text)) <= 120", name: "conversation_threads_title_length"
  end

  create_table "generation_runs", force: :cascade do |t|
    t.bigint "ai_platform_prompt_id"
    t.string "ai_provider", default: "mistral", null: false
    t.bigint "assistant_message_id"
    t.integer "attempts_count", default: 0, null: false
    t.datetime "completed_at"
    t.bigint "conversation_thread_id", null: false
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.string "idempotency_key", null: false
    t.bigint "personality_version_id", null: false
    t.jsonb "prompt_manifest", default: {}, null: false
    t.datetime "relationship_consolidated_at"
    t.datetime "relationship_update_processed_at"
    t.bigint "retry_of_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_message_id", null: false
    t.index ["ai_platform_prompt_id"], name: "index_generation_runs_on_ai_platform_prompt_id"
    t.index ["assistant_message_id"], name: "index_generation_runs_on_assistant_message_id", unique: true, where: "(assistant_message_id IS NOT NULL)"
    t.index ["conversation_thread_id", "status"], name: "index_generation_runs_on_conversation_thread_id_and_status"
    t.index ["conversation_thread_id"], name: "index_generation_runs_on_conversation_thread_id"
    t.index ["idempotency_key"], name: "index_generation_runs_on_idempotency_key", unique: true
    t.index ["personality_version_id"], name: "index_generation_runs_on_personality_version_id"
    t.index ["retry_of_id"], name: "index_generation_runs_on_retry_of_id", unique: true
    t.index ["user_message_id"], name: "index_generation_runs_on_user_message_id"
    t.check_constraint "ai_provider::text = ANY (ARRAY['mistral'::character varying, 'openai'::character varying]::text[])", name: "generation_runs_ai_provider"
    t.check_constraint "attempts_count >= 0", name: "generation_runs_attempts_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'stopped'::character varying]::text[])", name: "generation_runs_status"
  end

  create_table "initiative_attempts", force: :cascade do |t|
    t.string "ai_provider", null: false
    t.datetime "completed_at"
    t.bigint "conversation_thread_id", null: false
    t.datetime "created_at", null: false
    t.string "error_code"
    t.boolean "manual_trigger", default: false, null: false
    t.bigint "message_id"
    t.bigint "personality_id", null: false
    t.bigint "personality_version_id", null: false
    t.bigint "source_message_id", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "topic"
    t.datetime "updated_at", null: false
    t.index ["conversation_thread_id"], name: "index_initiative_attempts_on_conversation_thread_id"
    t.index ["message_id"], name: "index_initiative_attempts_on_message_id"
    t.index ["personality_id"], name: "index_active_initiative_attempts", unique: true, where: "((status)::text = ANY ((ARRAY['pending'::character varying, 'running'::character varying])::text[]))"
    t.index ["personality_id"], name: "index_initiative_attempts_on_personality_id"
    t.index ["personality_version_id"], name: "index_initiative_attempts_on_personality_version_id"
    t.index ["source_message_id"], name: "index_initiative_attempts_on_source_message_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'skipped'::character varying, 'failed'::character varying]::text[])", name: "initiative_attempts_status"
  end

  create_table "login_challenges", force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.string "code_digest", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "requested_ip"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_login_challenges_on_expires_at"
    t.index ["requested_ip", "created_at"], name: "index_login_challenges_on_requested_ip_and_created_at"
    t.index ["token"], name: "index_login_challenges_on_token", unique: true
    t.index ["user_id"], name: "index_login_challenges_on_user_id"
  end

  create_table "memories", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "importance", null: false
    t.string "kind", null: false
    t.datetime "last_recalled_at"
    t.text "normalized_content", null: false
    t.datetime "occurred_at"
    t.string "origin", null: false
    t.bigint "personality_id", null: false
    t.string "sensitivity", default: "normal", null: false
    t.string "status", default: "active", null: false
    t.bigint "supersedes_id"
    t.datetime "updated_at", null: false
    t.index ["personality_id", "kind", "normalized_content"], name: "index_current_memories_on_normalized_content", unique: true, where: "((status)::text = ANY ((ARRAY['active'::character varying, 'pending'::character varying])::text[]))"
    t.index ["personality_id", "status", "importance"], name: "index_memories_for_management"
    t.index ["personality_id"], name: "index_memories_on_personality_id"
    t.index ["supersedes_id"], name: "index_memories_on_supersedes_id"
    t.check_constraint "(status::text = 'deleted'::text) = (deleted_at IS NOT NULL)", name: "memories_deleted_at"
    t.check_constraint "char_length(btrim(content)) >= 1 AND char_length(btrim(content)) <= 500", name: "memories_content_length"
    t.check_constraint "importance >= 1 AND importance <= 100", name: "memories_importance"
    t.check_constraint "kind::text = ANY (ARRAY['fact'::character varying, 'preference'::character varying, 'shared_event'::character varying, 'relationship'::character varying, 'boundary'::character varying, 'other'::character varying]::text[])", name: "memories_kind"
    t.check_constraint "origin::text = ANY (ARRAY['model'::character varying, 'user'::character varying]::text[])", name: "memories_origin"
    t.check_constraint "sensitivity::text = ANY (ARRAY['normal'::character varying, 'sensitive'::character varying]::text[])", name: "memories_sensitivity"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'pending'::character varying, 'superseded'::character varying, 'deleted'::character varying]::text[])", name: "memories_status"
  end

  create_table "memory_extractions", force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.bigint "generation_run_id", null: false
    t.bigint "model_call_id"
    t.bigint "personality_id", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["generation_run_id"], name: "index_memory_extractions_on_generation_run_id", unique: true
    t.index ["model_call_id"], name: "index_memory_extractions_on_model_call_id"
    t.index ["personality_id"], name: "index_memory_extractions_on_personality_id"
    t.check_constraint "attempts_count >= 0", name: "memory_extractions_attempts_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'skipped'::character varying]::text[])", name: "memory_extractions_status"
  end

  create_table "memory_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "memory_id", null: false
    t.bigint "message_id", null: false
    t.datetime "updated_at", null: false
    t.index ["memory_id", "message_id"], name: "index_memory_sources_on_memory_id_and_message_id", unique: true
    t.index ["memory_id"], name: "index_memory_sources_on_memory_id"
    t.index ["message_id"], name: "index_memory_sources_on_message_id"
  end

  create_table "message_attachments", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.string "object_key", null: false
    t.string "original_filename"
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_message_attachments_on_message_id", unique: true
    t.index ["object_key"], name: "index_message_attachments_on_object_key", unique: true
    t.check_constraint "byte_size > 0 AND byte_size <= 10485760", name: "message_attachments_byte_size"
    t.check_constraint "content_type::text = ANY (ARRAY['image/jpeg'::character varying, 'image/png'::character varying, 'image/webp'::character varying]::text[])", name: "message_attachments_content_type"
  end

  create_table "message_images", force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.bigint "byte_size"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.datetime "generated_at"
    t.bigint "message_id", null: false
    t.string "model"
    t.string "object_key"
    t.string "provider_request_id"
    t.text "scene_description"
    t.string "source_avatar_object_key", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_message_images_on_message_id", unique: true
    t.index ["object_key"], name: "index_message_images_on_object_key", unique: true, where: "(object_key IS NOT NULL)"
    t.check_constraint "attempts_count >= 0", name: "message_images_attempts_count"
    t.check_constraint "byte_size IS NULL OR byte_size >= 0", name: "message_images_byte_size"
    t.check_constraint "status::text <> 'ready'::text OR object_key IS NOT NULL AND content_type IS NOT NULL AND byte_size IS NOT NULL AND generated_at IS NOT NULL", name: "message_images_ready_metadata"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'generating'::character varying, 'ready'::character varying, 'failed'::character varying, 'declined'::character varying]::text[])", name: "message_images_status"
  end

  create_table "messages", force: :cascade do |t|
    t.string "client_token"
    t.text "content", default: "", null: false
    t.bigint "conversation_thread_id", null: false
    t.datetime "created_at", null: false
    t.string "initiated_by"
    t.string "language", default: "und", null: false
    t.bigint "personality_version_id", null: false
    t.integer "position", null: false
    t.datetime "read_at"
    t.string "role", null: false
    t.string "status", default: "completed", null: false
    t.datetime "updated_at", null: false
    t.index ["client_token"], name: "index_messages_on_client_token", unique: true, where: "(client_token IS NOT NULL)"
    t.index ["conversation_thread_id", "position"], name: "index_messages_on_conversation_thread_id_and_position", unique: true
    t.index ["conversation_thread_id", "read_at"], name: "index_unread_initiative_messages", where: "(((initiated_by)::text = 'personality'::text) AND (read_at IS NULL))"
    t.index ["conversation_thread_id"], name: "index_messages_on_conversation_thread_id"
    t.index ["personality_version_id"], name: "index_messages_on_personality_version_id"
    t.check_constraint "\"position\" > 0", name: "messages_positive_position"
    t.check_constraint "char_length(content) <= 100000 AND (status::text <> 'completed'::text OR role::text = 'user'::text OR char_length(btrim(content)) > 0)", name: "messages_content"
    t.check_constraint "initiated_by IS NULL AND read_at IS NULL OR initiated_by::text = 'personality'::text AND role::text = 'assistant'::text", name: "messages_initiative_metadata"
    t.check_constraint "language::text = ANY (ARRAY['ru'::character varying, 'en'::character varying, 'und'::character varying]::text[])", name: "messages_language"
    t.check_constraint "role::text = ANY (ARRAY['user'::character varying, 'assistant'::character varying]::text[])", name: "messages_role"
    t.check_constraint "status::text = ANY (ARRAY['streaming'::character varying, 'completed'::character varying, 'failed'::character varying, 'stopped'::character varying]::text[])", name: "messages_status"
  end

  create_table "model_calls", force: :cascade do |t|
    t.integer "cached_input_tokens"
    t.datetime "completed_at"
    t.bigint "cost_microusd"
    t.datetime "created_at", null: false
    t.string "error_class"
    t.string "error_code"
    t.text "error_message"
    t.bigint "generation_run_id"
    t.integer "input_tokens"
    t.integer "latency_ms"
    t.string "model", null: false
    t.integer "output_tokens"
    t.bigint "personality_id"
    t.string "pricing_version"
    t.string "provider", null: false
    t.string "provider_request_id"
    t.string "purpose", null: false
    t.datetime "reservation_expires_at"
    t.bigint "reserved_cost_microusd", default: 0, null: false
    t.string "response_model"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["generation_run_id"], name: "index_model_calls_on_generation_run_id"
    t.index ["personality_id", "created_at"], name: "index_model_calls_on_personality_id_and_created_at"
    t.index ["personality_id"], name: "index_model_calls_on_personality_id"
    t.index ["provider_request_id"], name: "index_model_calls_on_provider_request_id", unique: true, where: "(provider_request_id IS NOT NULL)"
    t.index ["reservation_expires_at"], name: "index_model_calls_on_reservation_expires_at", where: "(((status)::text = 'pending'::text) AND (reserved_cost_microusd > 0))"
    t.index ["user_id", "created_at"], name: "index_model_calls_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_model_calls_on_user_id"
    t.check_constraint "(input_tokens IS NULL OR input_tokens >= 0) AND (cached_input_tokens IS NULL OR cached_input_tokens >= 0) AND (output_tokens IS NULL OR output_tokens >= 0) AND (cost_microusd IS NULL OR cost_microusd >= 0) AND (latency_ms IS NULL OR latency_ms >= 0) AND (cached_input_tokens IS NULL OR input_tokens IS NOT NULL) AND (cached_input_tokens IS NULL OR cached_input_tokens <= input_tokens)", name: "model_calls_nonnegative_usage"
    t.check_constraint "purpose::text = ANY (ARRAY['conversation'::character varying, 'memory_extraction'::character varying, 'memory_consolidation'::character varying, 'thread_summary'::character varying, 'initiative'::character varying, 'photo_planning'::character varying]::text[])", name: "model_calls_purpose"
    t.check_constraint "reserved_cost_microusd >= 0", name: "model_calls_nonnegative_reservation"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "model_calls_status"
  end

  create_table "model_prices", force: :cascade do |t|
    t.bigint "cached_input_microusd_per_million", null: false
    t.datetime "created_at", null: false
    t.datetime "effective_from", null: false
    t.datetime "effective_until"
    t.bigint "input_microusd_per_million", null: false
    t.string "model", null: false
    t.bigint "output_microusd_per_million", null: false
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["provider", "model", "effective_from"], name: "index_model_prices_on_provider_and_model_and_effective_from", unique: true
    t.index ["provider", "model", "effective_until"], name: "index_model_prices_on_provider_and_model_and_effective_until"
    t.check_constraint "effective_until IS NULL OR effective_until > effective_from", name: "model_prices_valid_interval"
    t.check_constraint "input_microusd_per_million >= 0 AND cached_input_microusd_per_million >= 0 AND output_microusd_per_million >= 0", name: "model_prices_nonnegative_rates"
  end

  create_table "outbox_events", force: :cascade do |t|
    t.jsonb "arguments", default: [], null: false
    t.integer "attempts_count", default: 0, null: false
    t.datetime "available_at", null: false
    t.datetime "created_at", null: false
    t.datetime "dispatched_at"
    t.string "event_key", null: false
    t.string "job_class", null: false
    t.text "last_error"
    t.datetime "locked_at"
    t.string "queue_name", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["event_key"], name: "index_outbox_events_on_event_key", unique: true
    t.index ["status", "available_at"], name: "index_outbox_events_for_dispatch"
    t.check_constraint "attempts_count >= 0", name: "outbox_events_attempts_count"
    t.check_constraint "jsonb_typeof(arguments) = 'array'::text", name: "outbox_events_arguments_array"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'processing'::character varying, 'dispatched'::character varying]::text[])", name: "outbox_events_status"
  end

  create_table "personalities", force: :cascade do |t|
    t.boolean "automatic_memory_enabled", default: true, null: false
    t.integer "avatar_attempts_count", default: 0, null: false
    t.bigint "avatar_byte_size"
    t.string "avatar_content_type"
    t.string "avatar_error_code"
    t.text "avatar_error_message"
    t.datetime "avatar_generated_at"
    t.string "avatar_object_key"
    t.bigint "avatar_source_version_id"
    t.datetime "avatar_started_at"
    t.string "avatar_status", default: "missing", null: false
    t.string "conversation_model", default: "mistral-large-2512", null: false
    t.datetime "created_at", null: false
    t.bigint "current_version_id"
    t.text "description", default: "", null: false
    t.integer "initiative_cooldown_hours", default: 72, null: false
    t.boolean "initiative_enabled", default: false, null: false
    t.integer "initiative_idle_hours", default: 24, null: false
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "utility_model", default: "mistral-small-latest", null: false
    t.index ["avatar_object_key"], name: "index_personalities_on_avatar_object_key", unique: true, where: "(avatar_object_key IS NOT NULL)"
    t.index ["avatar_source_version_id"], name: "index_personalities_on_avatar_source_version_id"
    t.index ["current_version_id"], name: "index_personalities_on_current_version_id", unique: true
    t.index ["initiative_enabled", "status"], name: "index_personalities_on_initiative_enabled_and_status"
    t.index ["user_id", "status"], name: "index_personalities_on_user_id_and_status"
    t.index ["user_id"], name: "index_personalities_on_user_id"
    t.check_constraint "avatar_attempts_count >= 0", name: "personalities_avatar_attempts_count"
    t.check_constraint "avatar_byte_size IS NULL OR avatar_byte_size >= 0", name: "personalities_avatar_byte_size"
    t.check_constraint "avatar_status::text <> 'ready'::text OR avatar_object_key IS NOT NULL AND avatar_content_type IS NOT NULL AND avatar_byte_size IS NOT NULL AND avatar_generated_at IS NOT NULL AND avatar_source_version_id IS NOT NULL", name: "personalities_ready_avatar_metadata"
    t.check_constraint "avatar_status::text = ANY (ARRAY['missing'::character varying, 'pending'::character varying, 'generating'::character varying, 'ready'::character varying, 'failed'::character varying]::text[])", name: "personalities_avatar_status"
    t.check_constraint "char_length(btrim(name::text)) >= 1 AND char_length(btrim(name::text)) <= 80", name: "personalities_name_length"
    t.check_constraint "char_length(description) <= 500", name: "personalities_description_length"
    t.check_constraint "initiative_cooldown_hours >= 24 AND initiative_cooldown_hours <= 720", name: "personalities_initiative_cooldown_hours"
    t.check_constraint "initiative_idle_hours >= 12 AND initiative_idle_hours <= 168", name: "personalities_initiative_idle_hours"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'active'::character varying, 'archived'::character varying]::text[])", name: "personalities_status"
  end

  create_table "personality_versions", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.text "change_note"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "number", null: false
    t.bigint "personality_id", null: false
    t.bigint "source_version_id"
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_personality_versions_on_author_id"
    t.index ["personality_id", "number"], name: "index_personality_versions_on_personality_id_and_number", unique: true
    t.index ["personality_id"], name: "index_personality_versions_on_personality_id"
    t.index ["source_version_id"], name: "index_personality_versions_on_source_version_id"
    t.check_constraint "change_note IS NULL OR char_length(change_note) <= 500", name: "personality_versions_change_note_length"
    t.check_constraint "char_length(btrim(content)) >= 1 AND char_length(btrim(content)) <= 50000", name: "personality_versions_content_length"
    t.check_constraint "number > 0", name: "personality_versions_positive_number"
  end

  create_table "profiles", force: :cascade do |t|
    t.date "birth_date"
    t.datetime "created_at", null: false
    t.string "first_name", null: false
    t.string "gender", null: false
    t.string "last_name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_profiles_on_user_id", unique: true
  end

  create_table "relationship_state_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "generation_run_id"
    t.bigint "model_call_id"
    t.string "reason", default: "model_update", null: false
    t.bigint "relationship_state_id", null: false
    t.integer "revision", null: false
    t.jsonb "source_message_ids", default: [], null: false
    t.bigint "source_version_id"
    t.text "summary", null: false
    t.datetime "updated_at", null: false
    t.index ["generation_run_id"], name: "index_relationship_state_versions_on_generation_run_id", unique: true
    t.index ["model_call_id"], name: "index_relationship_state_versions_on_model_call_id"
    t.index ["relationship_state_id", "revision"], name: "index_relationship_versions_on_state_and_revision", unique: true
    t.index ["relationship_state_id"], name: "index_relationship_state_versions_on_relationship_state_id"
    t.index ["source_version_id"], name: "index_relationship_state_versions_on_source_version_id"
    t.check_constraint "char_length(summary) <= 100000", name: "relationship_state_versions_summary_length"
    t.check_constraint "reason::text = ANY (ARRAY['model_update'::character varying, 'cleanup'::character varying, 'consolidation'::character varying, 'rollback'::character varying]::text[])", name: "relationship_state_versions_reason"
    t.check_constraint "revision > 0", name: "relationship_state_versions_revision"
  end

  create_table "relationship_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "last_consolidated_message_id"
    t.bigint "personality_id", null: false
    t.integer "revision", default: 0, null: false
    t.text "summary", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["personality_id"], name: "index_relationship_states_on_personality_id", unique: true
    t.check_constraint "char_length(summary) <= 100000", name: "relationship_states_summary_length"
    t.check_constraint "revision >= 0", name: "relationship_states_revision"
  end

  create_table "thread_summary_versions", force: :cascade do |t|
    t.bigint "conversation_thread_id", null: false
    t.datetime "created_at", null: false
    t.bigint "generation_run_id", null: false
    t.bigint "model_call_id"
    t.bigint "previous_version_id"
    t.integer "revision", null: false
    t.jsonb "source_message_ids", default: [], null: false
    t.text "summary", null: false
    t.bigint "through_message_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_thread_id", "revision"], name: "index_thread_summary_versions_on_thread_and_revision", unique: true
    t.index ["conversation_thread_id"], name: "index_thread_summary_versions_on_conversation_thread_id"
    t.index ["generation_run_id"], name: "index_thread_summary_versions_on_generation_run_id", unique: true
    t.index ["model_call_id"], name: "index_thread_summary_versions_on_model_call_id"
    t.index ["previous_version_id"], name: "index_thread_summary_versions_on_previous_version_id"
    t.index ["through_message_id"], name: "index_thread_summary_versions_on_through_message_id"
    t.check_constraint "char_length(btrim(summary)) >= 1 AND char_length(btrim(summary)) <= 100000", name: "thread_summary_versions_summary_length"
    t.check_constraint "revision > 0", name: "thread_summary_versions_revision"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "confirmation_sent_at"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "monthly_ai_limit_microusd", default: 20000000, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.check_constraint "monthly_ai_limit_microusd >= 0", name: "users_nonnegative_ai_limit"
  end

  add_foreign_key "ai_prompt_revisions", "users", column: "published_by_id", on_delete: :nullify
  add_foreign_key "conversation_threads", "messages", column: "summary_through_message_id", on_delete: :nullify
  add_foreign_key "conversation_threads", "personalities"
  add_foreign_key "generation_runs", "ai_platform_prompts", on_delete: :nullify
  add_foreign_key "generation_runs", "conversation_threads"
  add_foreign_key "generation_runs", "generation_runs", column: "retry_of_id", on_delete: :restrict
  add_foreign_key "generation_runs", "messages", column: "assistant_message_id", on_delete: :restrict
  add_foreign_key "generation_runs", "messages", column: "user_message_id", on_delete: :restrict
  add_foreign_key "generation_runs", "personality_versions"
  add_foreign_key "initiative_attempts", "conversation_threads", on_delete: :cascade
  add_foreign_key "initiative_attempts", "messages", column: "source_message_id", on_delete: :cascade
  add_foreign_key "initiative_attempts", "messages", on_delete: :nullify
  add_foreign_key "initiative_attempts", "personalities", on_delete: :cascade
  add_foreign_key "initiative_attempts", "personality_versions", on_delete: :restrict
  add_foreign_key "login_challenges", "users"
  add_foreign_key "memories", "memories", column: "supersedes_id", on_delete: :nullify
  add_foreign_key "memories", "personalities", on_delete: :cascade
  add_foreign_key "memory_extractions", "generation_runs", on_delete: :cascade
  add_foreign_key "memory_extractions", "model_calls", on_delete: :nullify
  add_foreign_key "memory_extractions", "personalities", on_delete: :cascade
  add_foreign_key "memory_sources", "memories", on_delete: :cascade
  add_foreign_key "memory_sources", "messages", on_delete: :cascade
  add_foreign_key "message_attachments", "messages", on_delete: :cascade
  add_foreign_key "message_images", "messages", on_delete: :cascade
  add_foreign_key "messages", "conversation_threads"
  add_foreign_key "messages", "personality_versions"
  add_foreign_key "model_calls", "generation_runs"
  add_foreign_key "model_calls", "personalities"
  add_foreign_key "model_calls", "users"
  add_foreign_key "personalities", "personality_versions", column: "avatar_source_version_id", on_delete: :nullify
  add_foreign_key "personalities", "personality_versions", column: "current_version_id", on_delete: :nullify
  add_foreign_key "personalities", "users"
  add_foreign_key "personality_versions", "personalities"
  add_foreign_key "personality_versions", "personality_versions", column: "source_version_id", on_delete: :nullify
  add_foreign_key "personality_versions", "users", column: "author_id"
  add_foreign_key "profiles", "users"
  add_foreign_key "relationship_state_versions", "generation_runs", on_delete: :nullify
  add_foreign_key "relationship_state_versions", "model_calls", on_delete: :nullify
  add_foreign_key "relationship_state_versions", "relationship_state_versions", column: "source_version_id", on_delete: :nullify
  add_foreign_key "relationship_state_versions", "relationship_states", on_delete: :cascade
  add_foreign_key "relationship_states", "personalities", on_delete: :cascade
  add_foreign_key "thread_summary_versions", "conversation_threads", on_delete: :cascade
  add_foreign_key "thread_summary_versions", "generation_runs", on_delete: :cascade
  add_foreign_key "thread_summary_versions", "messages", column: "through_message_id", on_delete: :restrict
  add_foreign_key "thread_summary_versions", "model_calls", on_delete: :nullify
  add_foreign_key "thread_summary_versions", "thread_summary_versions", column: "previous_version_id", on_delete: :nullify
end
