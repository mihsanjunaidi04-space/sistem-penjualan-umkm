class CreateWishlistItems < ActiveRecord::Migration[8.1]
  def change
    create_table :wishlist_items, force: true do |t|
      t.bigint :wishlist_id, null: false
      t.bigint :product_id, null: false
      t.timestamps null: false
    end
    add_index :wishlist_items, :wishlist_id
    add_index :wishlist_items, :product_id
    add_index :wishlist_items, [:wishlist_id, :product_id], unique: true
    add_foreign_key :wishlist_items, :wishlists, on_delete: :restrict
    add_foreign_key :wishlist_items, :products, on_delete: :restrict
  end
end
