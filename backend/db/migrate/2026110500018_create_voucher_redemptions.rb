class CreateVoucherRedemptions < ActiveRecord::Migration[8.1]
  def change
    create_table :voucher_redemptions, force: true do |t|
      t.bigint :voucher_id, null: false
      t.bigint :user_id, null: false
      t.bigint :order_id
      t.string :status, null: false, default: 'reserved', limit: 20
      t.datetime :reserved_at
      t.datetime :used_at
      t.datetime :released_at
      t.timestamps null: false
    end
    add_index :voucher_redemptions, :voucher_id
    add_index :voucher_redemptions, :user_id
    add_index :voucher_redemptions, :order_id, unique: true
    add_index :voucher_redemptions, :status
    add_foreign_key :voucher_redemptions, :vouchers, on_delete: :restrict
    add_foreign_key :voucher_redemptions, :users, on_delete: :restrict
    add_foreign_key :voucher_redemptions, :orders, on_delete: :restrict
    add_check_constraint :voucher_redemptions, "status IN ('reserved', 'used', 'released')", name: 'voucher_redemptions_status_check'
  end
end
