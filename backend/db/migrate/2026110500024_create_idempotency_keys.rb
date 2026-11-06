class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :idempotency_keys, force: true do |t|
      t.bigint :user_id, null: false
      t.string :key, null: false, limit: 180
      t.string :request_hash, null: false
      t.integer :response_status, null: false, default: 200
      t.text :response_body
      t.string :resource_type, limit: 80
      t.string :resource_id, limit: 120
      t.datetime :expires_at, null: false
      t.timestamps null: false
    end
    add_index :idempotency_keys, :user_id
    add_index :idempotency_keys, [ :user_id, :key ], unique: true
    add_index :idempotency_keys, :expires_at
    add_foreign_key :idempotency_keys, :users, on_delete: :restrict
    add_check_constraint :idempotency_keys, 'response_status >= 100', name: 'idempotency_keys_response_status_minimum'
  end
end
