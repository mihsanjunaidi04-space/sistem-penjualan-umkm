class CreateShipments < ActiveRecord::Migration[8.1]
  def change
    create_table :shipments, force: true do |t|
      t.bigint :order_id, null: false
      t.bigint :shipping_method_id, null: false
      t.string :recipient_name_snapshot, null: false, limit: 150
      t.text :shipping_address_snapshot, null: false
      t.string :tracking_number, limit: 120
      t.string :status, null: false, default: 'not_shipped', limit: 30
      t.datetime :shipped_at
      t.datetime :delivered_at
      t.timestamps null: false
    end
    add_index :shipments, :order_id, unique: true
    add_index :shipments, :shipping_method_id
    add_index :shipments, :status
    add_foreign_key :shipments, :orders, on_delete: :restrict
    add_foreign_key :shipments, :shipping_methods, on_delete: :restrict
    add_check_constraint :shipments, "status IN ('not_shipped', 'packed', 'shipped', 'delivered')", name: 'shipments_status_check'
  end
end
