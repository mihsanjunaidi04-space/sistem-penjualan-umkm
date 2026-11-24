class CreateRefundIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :refund_idempotency_keys do |t|
      t.bigint :admin_id, null: false
      t.bigint :payment_id, null: false
      t.bigint :refund_id, null: false
      t.string :key, null: false, limit: 180
      t.string :request_hash, null: false, limit: 64
      t.timestamps null: false
    end

    add_index :refund_idempotency_keys, [ :admin_id, :payment_id, :key ], unique: true, name: "index_refund_idempotency_keys_on_scope_and_key"
    add_index :refund_idempotency_keys, :refund_id, unique: true
    add_foreign_key :refund_idempotency_keys, :users, column: :admin_id, on_delete: :restrict
    add_foreign_key :refund_idempotency_keys, :payments, on_delete: :restrict
    add_foreign_key :refund_idempotency_keys, :refunds, on_delete: :restrict
    add_check_constraint :refund_idempotency_keys, "length(key) BETWEEN 1 AND 180", name: "refund_idempotency_keys_key_length"
    add_check_constraint :refund_idempotency_keys, "length(request_hash) = 64", name: "refund_idempotency_keys_hash_length"
  end
end
