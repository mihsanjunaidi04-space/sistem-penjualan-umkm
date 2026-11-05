class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments, force: true do |t|
      t.bigint :order_id, null: false
      t.string :payment_method, null: false, limit: 40
      t.integer :amount, null: false
      t.string :status, null: false, default: 'pending', limit: 30
      t.bigint :verified_by
      t.datetime :verified_at
      t.text :rejection_reason
      t.timestamps null: false
    end
    add_index :payments, :order_id, unique: true
    add_index :payments, :status
    add_index :payments, :verified_by
    add_foreign_key :payments, :orders, on_delete: :restrict
    add_foreign_key :payments, :users, column: :verified_by, primary_key: :id, on_delete: :restrict
    add_check_constraint :payments, 'amount >= 0', name: 'payments_amount_non_negative'
    add_check_constraint :payments, "status IN ('pending', 'waiting_verification', 'paid', 'rejected', 'expired', 'refunded')", name: 'payments_status_check'
  end
end
