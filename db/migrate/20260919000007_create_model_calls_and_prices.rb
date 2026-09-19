class CreateModelCallsAndPrices < ActiveRecord::Migration[8.1]
  def change
    add_column :personalities, :conversation_model, :string, null: false, default: "gpt-4o"
    add_column :personalities, :utility_model, :string, null: false, default: "gpt-4o-mini"

    create_table :model_prices do |t|
      t.string :provider, null: false
      t.string :model, null: false
      t.string :version, null: false
      t.bigint :input_microusd_per_million, null: false
      t.bigint :cached_input_microusd_per_million, null: false
      t.bigint :output_microusd_per_million, null: false
      t.datetime :effective_from, null: false
      t.datetime :effective_until
      t.timestamps
    end

    add_index :model_prices, %i[provider model effective_from], unique: true
    add_index :model_prices, %i[provider model effective_until]
    add_check_constraint :model_prices,
                         "input_microusd_per_million >= 0 AND " \
                         "cached_input_microusd_per_million >= 0 AND " \
                         "output_microusd_per_million >= 0",
                         name: "model_prices_nonnegative_rates"
    add_check_constraint :model_prices,
                         "effective_until IS NULL OR effective_until > effective_from",
                         name: "model_prices_valid_interval"

    create_table :model_calls do |t|
      t.references :user, null: false, foreign_key: true
      t.references :personality, foreign_key: true
      t.references :generation_run, foreign_key: true
      t.string :purpose, null: false
      t.string :provider, null: false
      t.string :model, null: false
      t.string :provider_request_id
      t.string :status, null: false, default: "pending"
      t.integer :input_tokens
      t.integer :cached_input_tokens
      t.integer :output_tokens
      t.bigint :cost_microusd
      t.string :pricing_version
      t.integer :latency_ms
      t.string :error_class
      t.string :error_code
      t.text :error_message
      t.datetime :completed_at
      t.timestamps
    end

    add_index :model_calls, %i[user_id created_at]
    add_index :model_calls, %i[personality_id created_at]
    add_index :model_calls, :provider_request_id,
              unique: true,
              where: "provider_request_id IS NOT NULL"
    add_check_constraint :model_calls,
                         "purpose IN ('conversation', 'memory_extraction', " \
                         "'memory_consolidation', 'thread_summary', 'initiative')",
                         name: "model_calls_purpose"
    add_check_constraint :model_calls,
                         "status IN ('pending', 'completed', 'failed')",
                         name: "model_calls_status"
    add_check_constraint :model_calls,
                         <<~SQL.squish,
                           (input_tokens IS NULL OR input_tokens >= 0) AND
                           (cached_input_tokens IS NULL OR cached_input_tokens >= 0) AND
                           (output_tokens IS NULL OR output_tokens >= 0) AND
                           (cost_microusd IS NULL OR cost_microusd >= 0) AND
                           (latency_ms IS NULL OR latency_ms >= 0) AND
                           (cached_input_tokens IS NULL OR input_tokens IS NOT NULL) AND
                           (cached_input_tokens IS NULL OR cached_input_tokens <= input_tokens)
                         SQL
                         name: "model_calls_nonnegative_usage"
  end
end
