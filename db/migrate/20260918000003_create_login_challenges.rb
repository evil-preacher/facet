class CreateLoginChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :login_challenges do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.integer :attempts_count, null: false, default: 0
      t.datetime :consumed_at
      t.string :requested_ip

      t.timestamps
    end

    add_index :login_challenges, :token, unique: true
    add_index :login_challenges, :expires_at
    add_index :login_challenges, [ :requested_ip, :created_at ]
  end
end
