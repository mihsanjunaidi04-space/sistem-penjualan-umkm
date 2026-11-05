class CreateWishlists < ActiveRecord::Migration[8.1]
  def change
    create_table :wishlists, force: true do |t|
      t.bigint :user_id, null: false
      t.timestamps null: false
    end
    add_index :wishlists, :user_id, unique: true
    add_foreign_key :wishlists, :users, on_delete: :restrict
  end
end
