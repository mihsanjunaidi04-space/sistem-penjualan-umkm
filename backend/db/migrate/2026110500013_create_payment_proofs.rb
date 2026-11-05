class CreatePaymentProofs < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_proofs, force: true do |t|
      t.bigint :payment_id, null: false
      t.string :storage_key, null: false
      t.string :original_filename, null: false, limit: 255
      t.string :mime_type, limit: 120
      t.integer :file_size, null: false, default: 0
      t.string :status, null: false, default: 'submitted', limit: 30
      t.datetime :uploaded_at, null: false
      t.datetime :reviewed_at
      t.timestamps null: false
    end
    add_index :payment_proofs, :payment_id
    add_index :payment_proofs, :status
    add_foreign_key :payment_proofs, :payments, on_delete: :restrict
    add_check_constraint :payment_proofs, 'file_size >= 0', name: 'payment_proofs_file_size_non_negative'
    add_check_constraint :payment_proofs, "status IN ('submitted', 'approved', 'rejected')", name: 'payment_proofs_status_check'
  end
end
