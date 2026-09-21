class CreateMessageImages < ActiveRecord::Migration[8.1]
  def change
    create_table :message_images do |t|
      t.references :message, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :status, null: false, default: "pending"
      t.string :source_avatar_object_key, null: false
      t.string :object_key
      t.string :content_type
      t.bigint :byte_size
      t.integer :attempts_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :generated_at
      t.string :provider_request_id
      t.string :model
      t.string :error_code
      t.text :error_message
      t.timestamps
    end

    add_index :message_images, :object_key, unique: true, where: "object_key IS NOT NULL"
    add_check_constraint :message_images,
                         "status IN ('pending', 'generating', 'ready', 'failed')",
                         name: "message_images_status"
    add_check_constraint :message_images,
                         "attempts_count >= 0",
                         name: "message_images_attempts_count"
    add_check_constraint :message_images,
                         "byte_size IS NULL OR byte_size >= 0",
                         name: "message_images_byte_size"
    add_check_constraint :message_images,
                         <<~SQL.squish,
                           status <> 'ready' OR (
                             object_key IS NOT NULL AND
                             content_type IS NOT NULL AND
                             byte_size IS NOT NULL AND
                             generated_at IS NOT NULL
                           )
                         SQL
                         name: "message_images_ready_metadata"
  end
end
