class CreateRefunds < ActiveRecord::Migration[8.1]
  def change
    create_table :refunds, force: true do |t|
      t.bigint :payment_id, null: false
      t.bigint :order_id, null: false
      t.integer :amount, null: false
      t.text :reason, null: false
      t.string :status, null: false, default: 'pending', limit: 20
      t.bigint :processed_by
      t.datetime :processed_at
      t.string :reference_number, limit: 80
      t.text :notes
      t.timestamps null: false
    end
    add_index :refunds, :payment_id
    add_index :refunds, :order_id
    add_index :refunds, :status
    add_index :refunds, :processed_by
    add_foreign_key :refunds, :payments, on_delete: :restrict
    add_foreign_key :refunds, :orders, on_delete: :restrict
    add_foreign_key :refunds, :users, column: :processed_by, primary_key: :id, on_delete: :restrict
    add_check_constraint :refunds, 'amount > 0', name: 'refunds_amount_positive'
    add_check_constraint :refunds, "status IN ('pending', 'processed', 'rejected')", name: 'refunds_status_check'
    # D2 refund policy pending final decision; keep database schema neutral and enforce refund rules in transactional service logic.
  end
end
