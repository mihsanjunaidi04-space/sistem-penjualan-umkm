class CreatePasswordResetTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :password_reset_tokens, force: true do |t|
      t.bigint :user_id, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps null: false
    end
    add_index :password_reset_tokens, :user_id
    add_foreign_key :password_reset_tokens, :users, on_delete: :restrict
  end
end
