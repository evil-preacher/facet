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

ActiveRecord::Schema[8.1].define(version: 2026_09_19_000014) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.bigint "retry_of_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_message_id", null: false
    t.index ["assistant_message_id"], name: "index_generation_runs_on_assistant_message_id", unique: true, where: "(assistant_message_id IS NOT NULL)"
    t.index ["conversation_thread_id", "status"], name: "index_generation_runs_on_conversation_thread_id_and_status"
    t.index ["conversation_thread_id"], name: "index_generation_runs_on_conversation_thread_id"
    t.index ["idempotency_key"], name: "index_generation_runs_on_idempotency_key", unique: true
    t.index ["personality_version_id"], name: "index_generation_runs_on_personality_version_id"
    t.index ["retry_of_id"], name: "index_generation_runs_on_retry_of_id", unique: true
    t.index ["user_message_id"], name: "index_generation_runs_on_user_message_id"
    t.check_constraint "attempts_count >= 0", name: "generation_runs_attempts_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'stopped'::character varying]::text[])", name: "generation_runs_status"
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

  create_table "messages", force: :cascade do |t|
    t.string "client_token"
    t.text "content", default: "", null: false
    t.bigint "conversation_thread_id", null: false
    t.datetime "created_at", null: false
    t.string "language", default: "und", null: false
    t.bigint "personality_version_id", null: false
    t.integer "position", null: false
    t.string "role", null: false
    t.string "status", default: "completed", null: false
    t.datetime "updated_at", null: false
    t.index ["client_token"], name: "index_messages_on_client_token", unique: true, where: "(client_token IS NOT NULL)"
    t.index ["conversation_thread_id", "position"], name: "index_messages_on_conversation_thread_id_and_position", unique: true
    t.index ["conversation_thread_id"], name: "index_messages_on_conversation_thread_id"
    t.index ["personality_version_id"], name: "index_messages_on_personality_version_id"
    t.check_constraint "\"position\" > 0", name: "messages_positive_position"
    t.check_constraint "char_length(content) <= 100000 AND (status::text <> 'completed'::text OR char_length(btrim(content)) > 0)", name: "messages_content"
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
    t.string "response_model"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["generation_run_id"], name: "index_model_calls_on_generation_run_id"
    t.index ["personality_id", "created_at"], name: "index_model_calls_on_personality_id_and_created_at"
    t.index ["personality_id"], name: "index_model_calls_on_personality_id"
    t.index ["provider_request_id"], name: "index_model_calls_on_provider_request_id", unique: true, where: "(provider_request_id IS NOT NULL)"
    t.index ["user_id", "created_at"], name: "index_model_calls_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_model_calls_on_user_id"
    t.check_constraint "(input_tokens IS NULL OR input_tokens >= 0) AND (cached_input_tokens IS NULL OR cached_input_tokens >= 0) AND (output_tokens IS NULL OR output_tokens >= 0) AND (cost_microusd IS NULL OR cost_microusd >= 0) AND (latency_ms IS NULL OR latency_ms >= 0) AND (cached_input_tokens IS NULL OR input_tokens IS NOT NULL) AND (cached_input_tokens IS NULL OR cached_input_tokens <= input_tokens)", name: "model_calls_nonnegative_usage"
    t.check_constraint "purpose::text = ANY (ARRAY['conversation'::character varying, 'memory_extraction'::character varying, 'memory_consolidation'::character varying, 'thread_summary'::character varying, 'initiative'::character varying]::text[])", name: "model_calls_purpose"
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
    t.string "conversation_model", default: "mistral-large-2512", null: false
    t.datetime "created_at", null: false
    t.bigint "current_version_id"
    t.text "description", default: "", null: false
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "utility_model", default: "mistral-small-latest", null: false
    t.index ["current_version_id"], name: "index_personalities_on_current_version_id", unique: true
    t.index ["user_id", "status"], name: "index_personalities_on_user_id_and_status"
    t.index ["user_id"], name: "index_personalities_on_user_id"
    t.check_constraint "char_length(btrim(name::text)) >= 1 AND char_length(btrim(name::text)) <= 80", name: "personalities_name_length"
    t.check_constraint "char_length(description) <= 500", name: "personalities_description_length"
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

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "conversation_threads", "messages", column: "summary_through_message_id", on_delete: :nullify
  add_foreign_key "conversation_threads", "personalities"
  add_foreign_key "generation_runs", "conversation_threads"
  add_foreign_key "generation_runs", "generation_runs", column: "retry_of_id", on_delete: :restrict
  add_foreign_key "generation_runs", "messages", column: "assistant_message_id", on_delete: :restrict
  add_foreign_key "generation_runs", "messages", column: "user_message_id", on_delete: :restrict
  add_foreign_key "generation_runs", "personality_versions"
  add_foreign_key "login_challenges", "users"
  add_foreign_key "messages", "conversation_threads"
  add_foreign_key "messages", "personality_versions"
  add_foreign_key "model_calls", "generation_runs"
  add_foreign_key "model_calls", "personalities"
  add_foreign_key "model_calls", "users"
  add_foreign_key "personalities", "personality_versions", column: "current_version_id", on_delete: :nullify
  add_foreign_key "personalities", "users"
  add_foreign_key "personality_versions", "personalities"
  add_foreign_key "personality_versions", "personality_versions", column: "source_version_id", on_delete: :nullify
  add_foreign_key "personality_versions", "users", column: "author_id"
  add_foreign_key "profiles", "users"
end
