class CreateVouchers < ActiveRecord::Migration[8.1]
  def change
    create_table :vouchers, force: true do |t|
      t.string :code, null: false, limit: 80
      t.text :description
      t.string :discount_type, null: false, limit: 20
      t.integer :discount_value, null: false, default: 0
      t.integer :minimum_purchase, null: false, default: 0
      t.integer :maximum_discount, null: false, default: 0
      t.integer :usage_limit, null: false, default: 0
      t.integer :per_user_limit, null: false, default: 0
      t.datetime :starts_at
      t.datetime :expires_at
      t.boolean :is_active, null: false, default: true
      t.timestamps null: false
    end
    add_index :vouchers, :code, unique: true
    add_index :vouchers, :is_active
    add_check_constraint :vouchers, "discount_type IN ('fixed', 'percentage')", name: 'vouchers_discount_type_check'
    add_check_constraint :vouchers, 'discount_value >= 0', name: 'vouchers_discount_value_non_negative'
    add_check_constraint :vouchers, 'minimum_purchase >= 0', name: 'vouchers_minimum_purchase_non_negative'
    add_check_constraint :vouchers, 'maximum_discount >= 0', name: 'vouchers_maximum_discount_non_negative'
    add_check_constraint :vouchers, 'usage_limit >= 0', name: 'vouchers_usage_limit_non_negative'
    add_check_constraint :vouchers, 'per_user_limit >= 0', name: 'vouchers_per_user_limit_non_negative'
  end
end
