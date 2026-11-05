class CreateCartItems < ActiveRecord::Migration[8.1]
  def change
    create_table :cart_items, force: true do |t|
      t.bigint :cart_id, null: false
      t.bigint :product_id, null: false
      t.integer :quantity, null: false
      t.timestamps null: false
    end
    add_index :cart_items, :cart_id
    add_index :cart_items, :product_id
    add_index :cart_items, [:cart_id, :product_id], unique: true
    add_foreign_key :cart_items, :carts, on_delete: :restrict
    add_foreign_key :cart_items, :products, on_delete: :restrict
    add_check_constraint :cart_items, 'quantity > 0', name: 'cart_items_quantity_positive'
  end
end
