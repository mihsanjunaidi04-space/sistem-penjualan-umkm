class CreateCancellationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :cancellation_requests, force: true do |t|
      t.bigint :order_id, null: false
      t.bigint :requested_by, null: false
      t.text :reason, null: false
      t.string :status, null: false, default: 'pending', limit: 20
      t.bigint :reviewed_by
      t.datetime :reviewed_at
      t.text :admin_note
      t.timestamps null: false
    end
    add_index :cancellation_requests, :order_id
    add_index :cancellation_requests, :requested_by
    add_index :cancellation_requests, :reviewed_by
    add_index :cancellation_requests, :status
    add_foreign_key :cancellation_requests, :orders, on_delete: :restrict
    add_foreign_key :cancellation_requests, :users, column: :requested_by, primary_key: :id, on_delete: :restrict
    add_foreign_key :cancellation_requests, :users, column: :reviewed_by, primary_key: :id, on_delete: :restrict
    add_check_constraint :cancellation_requests, "status IN ('pending', 'approved', 'rejected')", name: 'cancellation_requests_status_check'
  end
end
