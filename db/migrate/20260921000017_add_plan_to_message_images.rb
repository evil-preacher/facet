class AddPlanToMessageImages < ActiveRecord::Migration[8.1]
  def change
    add_column :message_images, :scene_description, :text

    remove_check_constraint :message_images, name: "message_images_status"
    add_check_constraint :message_images,
                         "status IN ('pending', 'generating', 'ready', 'failed', 'declined')",
                         name: "message_images_status"
  end
end
