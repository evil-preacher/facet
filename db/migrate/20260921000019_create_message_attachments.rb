class CreateMessageAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :message_attachments do |t|
      t.references :message, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :object_key, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :original_filename
      t.timestamps
    end

    add_index :message_attachments, :object_key, unique: true
    add_check_constraint :message_attachments,
                         "content_type IN ('image/jpeg', 'image/png', 'image/webp')",
                         name: "message_attachments_content_type"
    add_check_constraint :message_attachments,
                         "byte_size > 0 AND byte_size <= 10485760",
                         name: "message_attachments_byte_size"
  end
end
