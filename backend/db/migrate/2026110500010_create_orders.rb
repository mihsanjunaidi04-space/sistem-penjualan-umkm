class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders, force: true do |t|
      t.string :order_number, null: false, limit: 80
      t.bigint :user_id, null: false
      t.bigint :shipping_method_id, null: false
      t.string :status, null: false, default: 'awaiting_payment', limit: 30
      t.integer :subtotal, null: false, default: 0
      t.integer :discount_amount, null: false, default: 0
      t.integer :shipping_cost, null: false, default: 0
      t.integer :total_amount, null: false, default: 0
      t.string :voucher_code_snapshot, limit: 80
      t.string :recipient_name_snapshot, limit: 150
      t.string :recipient_phone_snapshot, limit: 30
      t.text :shipping_address_snapshot
      t.text :customer_notes
      t.datetime :payment_deadline_at, null: false
      t.datetime :shipped_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.timestamps null: false
    end
    add_index :orders, :order_number, unique: true
    add_index :orders, :user_id
    add_index :orders, :shipping_method_id
    add_index :orders, :status
    add_index :orders, :created_at
    add_foreign_key :orders, :users, on_delete: :restrict
    add_foreign_key :orders, :shipping_methods, on_delete: :restrict
    add_check_constraint :orders, 'subtotal >= 0', name: 'orders_subtotal_non_negative'
    add_check_constraint :orders, 'discount_amount >= 0', name: 'orders_discount_amount_non_negative'
    add_check_constraint :orders, 'shipping_cost >= 0', name: 'orders_shipping_cost_non_negative'
    add_check_constraint :orders, 'total_amount >= 0', name: 'orders_total_amount_non_negative'
    add_check_constraint :orders, "status IN ('awaiting_payment', 'processing', 'shipped', 'completed', 'cancelled')", name: 'orders_status_check'
  end
end
