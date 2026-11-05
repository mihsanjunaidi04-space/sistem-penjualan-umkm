class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products, force: true do |t|
      t.bigint :category_id, null: false
      t.string :name, null: false, limit: 180
      t.string :slug, null: false, limit: 180
      t.string :sku, null: false, limit: 120
      t.text :description
      t.integer :price, null: false, default: 0
      t.integer :stock_on_hand, null: false, default: 0
      t.integer :reserved_stock, null: false, default: 0
      t.boolean :is_active, null: false, default: true
      t.timestamps null: false
    end
    add_index :products, :category_id
    add_index :products, :slug, unique: true
    add_index :products, :sku, unique: true
    add_foreign_key :products, :categories, on_delete: :restrict
    add_check_constraint :products, 'price >= 0', name: 'products_price_non_negative'
    add_check_constraint :products, 'stock_on_hand >= 0', name: 'products_stock_on_hand_non_negative'
    add_check_constraint :products, 'reserved_stock >= 0', name: 'products_reserved_stock_non_negative'
    add_check_constraint :products, 'reserved_stock <= stock_on_hand', name: 'products_reserved_stock_within_stock'
  end
end
