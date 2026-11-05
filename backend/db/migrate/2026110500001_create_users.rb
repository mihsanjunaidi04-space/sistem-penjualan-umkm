class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, force: true do |t|
      t.string :name, null: false, limit: 150
      t.string :email, null: false, limit: 255
      t.string :password_digest, null: false
      t.string :role, null: false, default: 'customer', limit: 20
      t.string :phone, limit: 30
      t.boolean :is_active, null: false, default: true
      t.datetime :email_verified_at
      t.timestamps null: false
    end
    add_index :users, :email, unique: true
    add_check_constraint :users, "role IN ('admin', 'customer')", name: 'users_role_check'
  end
end
