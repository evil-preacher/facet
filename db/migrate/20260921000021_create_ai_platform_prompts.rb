class CreateAiPlatformPrompts < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_platform_prompts do |t|
      t.string :provider, null: false
      t.string :purpose, null: false, default: "conversation"
      t.integer :revision, null: false
      t.text :content, null: false
      t.string :checksum, null: false
      t.string :status, null: false, default: "active"
      t.datetime :published_at

      t.timestamps
    end

    add_index :ai_platform_prompts, %i[provider purpose revision], unique: true
    add_index :ai_platform_prompts,
              %i[provider purpose],
              unique: true,
              where: "status = 'active'",
              name: "index_ai_platform_prompts_on_active_scope"
    add_check_constraint :ai_platform_prompts,
                         "provider IN ('mistral', 'openai')",
                         name: "ai_platform_prompts_provider"
    add_check_constraint :ai_platform_prompts,
                         "purpose IN ('conversation')",
                         name: "ai_platform_prompts_purpose"
    add_check_constraint :ai_platform_prompts,
                         "status IN ('active', 'retired')",
                         name: "ai_platform_prompts_status"
    add_check_constraint :ai_platform_prompts,
                         "revision > 0",
                         name: "ai_platform_prompts_positive_revision"
    add_check_constraint :ai_platform_prompts,
                         "char_length(btrim(content)) BETWEEN 1 AND 20000",
                         name: "ai_platform_prompts_content_length"

    add_column :generation_runs, :ai_provider, :string, null: false, default: "mistral"
    add_reference :generation_runs,
                  :ai_platform_prompt,
                  foreign_key: { on_delete: :nullify },
                  index: true
    add_check_constraint :generation_runs,
                         "ai_provider IN ('mistral', 'openai')",
                         name: "generation_runs_ai_provider"
  end
end
