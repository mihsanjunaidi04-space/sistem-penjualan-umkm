class CreatePaymentVerificationEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_verification_events, force: true do |t|
      t.bigint :payment_id, null: false
      t.bigint :payment_proof_id
      t.bigint :admin_id, null: false
      t.string :decision, null: false, limit: 20
      t.text :reason
      t.datetime :created_at, null: false
    end
    add_index :payment_verification_events, :payment_id
    add_index :payment_verification_events, :payment_proof_id
    add_index :payment_verification_events, :admin_id
    add_foreign_key :payment_verification_events, :payments, on_delete: :restrict
    add_foreign_key :payment_verification_events, :payment_proofs, on_delete: :restrict
    add_foreign_key :payment_verification_events, :users, column: :admin_id, on_delete: :restrict
    add_check_constraint :payment_verification_events, "decision IN ('approved', 'rejected')", name: 'payment_verification_events_decision_check'
  end
end
