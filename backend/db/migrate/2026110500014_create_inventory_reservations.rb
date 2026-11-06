class CreateInventoryReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :inventory_reservations, force: true do |t|
      t.bigint :order_id, null: false
      t.bigint :product_id, null: false
      t.integer :quantity, null: false
      t.string :status, null: false, default: 'reserved', limit: 30
      t.datetime :expires_at
      t.datetime :converted_at
      t.datetime :released_at
      t.timestamps null: false
    end
    add_index :inventory_reservations, :order_id
    add_index :inventory_reservations, :product_id
    add_index :inventory_reservations, :status
    add_index :inventory_reservations, :expires_at
    add_index :inventory_reservations, [ :order_id, :product_id ], unique: true
    add_foreign_key :inventory_reservations, :orders, on_delete: :restrict
    add_foreign_key :inventory_reservations, :products, on_delete: :restrict
    add_check_constraint :inventory_reservations, 'quantity > 0', name: 'inventory_reservations_quantity_positive'
    add_check_constraint :inventory_reservations, "status IN ('reserved', 'converted', 'released')", name: 'inventory_reservations_status_check'
  end
end
