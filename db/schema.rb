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

ActiveRecord::Schema[8.1].define(version: 2026_09_18_000005) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "personalities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "current_version_id"
    t.text "description", default: "", null: false
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["current_version_id"], name: "index_personalities_on_current_version_id", unique: true
    t.index ["user_id", "status"], name: "index_personalities_on_user_id_and_status"
    t.index ["user_id"], name: "index_personalities_on_user_id"
    t.check_constraint "char_length(btrim(name::text)) >= 1 AND char_length(btrim(name::text)) <= 80", name: "personalities_name_length"
    t.check_constraint "char_length(description) <= 500", name: "personalities_description_length"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'active'::character varying::text, 'archived'::character varying::text])", name: "personalities_status"
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
    t.check_constraint "char_length(btrim(content)) >= 1 AND char_length(btrim(content)) <= 20000", name: "personality_versions_content_length"
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

  add_foreign_key "login_challenges", "users"
  add_foreign_key "personalities", "personality_versions", column: "current_version_id", on_delete: :nullify
  add_foreign_key "personalities", "users"
  add_foreign_key "personality_versions", "personalities"
  add_foreign_key "personality_versions", "personality_versions", column: "source_version_id", on_delete: :nullify
  add_foreign_key "personality_versions", "users", column: "author_id"
  add_foreign_key "profiles", "users"
end
