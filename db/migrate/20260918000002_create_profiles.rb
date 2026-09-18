class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :gender, null: false
      t.date :birth_date

      t.timestamps
    end
  end
end
