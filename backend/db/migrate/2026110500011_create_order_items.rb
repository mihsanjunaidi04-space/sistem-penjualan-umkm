class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_items, force: true do |t|
      t.bigint :order_id, null: false
      t.bigint :product_id, null: false
      t.string :product_name_snapshot, null: false, limit: 180
      t.string :sku_snapshot, null: false, limit: 120
      t.integer :unit_price, null: false
      t.integer :quantity, null: false
      t.integer :subtotal, null: false
      t.timestamps null: false
    end
    add_index :order_items, :order_id
    add_index :order_items, :product_id
    add_index :order_items, [:order_id, :product_id], unique: true
    add_foreign_key :order_items, :orders, on_delete: :restrict
    add_foreign_key :order_items, :products, on_delete: :restrict
    add_check_constraint :order_items, 'unit_price >= 0', name: 'order_items_unit_price_non_negative'
    add_check_constraint :order_items, 'quantity > 0', name: 'order_items_quantity_positive'
    add_check_constraint :order_items, 'subtotal >= 0', name: 'order_items_subtotal_non_negative'
  end
end
