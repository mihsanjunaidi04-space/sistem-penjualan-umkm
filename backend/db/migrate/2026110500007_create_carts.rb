class CreateCarts < ActiveRecord::Migration[8.1]
  def change
    create_table :carts, force: true do |t|
      t.bigint :user_id, null: false
      t.timestamps null: false
    end
    add_index :carts, :user_id, unique: true
    add_foreign_key :carts, :users, on_delete: :restrict
  end
end
