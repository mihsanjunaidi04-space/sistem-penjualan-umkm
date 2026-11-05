class CreateShippingMethods < ActiveRecord::Migration[8.1]
  def change
    create_table :shipping_methods, force: true do |t|
      t.string :name, null: false, limit: 120
      t.text :description
      t.integer :estimated_days, null: false
      t.integer :cost, null: false, default: 0
      t.boolean :is_active, null: false, default: true
      t.timestamps null: false
    end
    add_index :shipping_methods, :name, unique: true
    add_check_constraint :shipping_methods, 'estimated_days > 0', name: 'shipping_methods_estimated_days_positive'
    add_check_constraint :shipping_methods, 'cost >= 0', name: 'shipping_methods_cost_non_negative'
  end
end
