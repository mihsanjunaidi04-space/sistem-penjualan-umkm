class CreateInventoryMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :inventory_movements, force: true do |t|
      t.bigint :product_id, null: false
      t.bigint :order_id
      t.string :movement_type, null: false, limit: 40
      t.integer :quantity, null: false
      t.integer :stock_before, null: false
      t.integer :stock_after, null: false
      t.string :reference, limit: 120
      t.text :notes
      t.bigint :created_by
      t.timestamps null: false
    end
    add_index :inventory_movements, :product_id
    add_index :inventory_movements, :order_id
    add_index :inventory_movements, :created_by
    add_foreign_key :inventory_movements, :products, on_delete: :restrict
    add_foreign_key :inventory_movements, :orders, on_delete: :restrict
    add_foreign_key :inventory_movements, :users, column: :created_by, primary_key: :id, on_delete: :restrict
    add_check_constraint :inventory_movements, "movement_type IN ('stock_in', 'stock_out', 'reservation', 'reservation_release', 'reservation_conversion', 'adjustment', 'return')", name: 'inventory_movements_type_check'
    add_check_constraint :inventory_movements, 'quantity != 0', name: 'inventory_movements_quantity_non_zero'
  end
end
