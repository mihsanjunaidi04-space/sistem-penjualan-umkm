class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews, force: true do |t|
      t.bigint :user_id, null: false
      t.bigint :product_id, null: false
      t.bigint :order_item_id, null: false
      t.integer :rating, null: false
      t.text :comment
      t.boolean :is_visible, null: false, default: true
      t.timestamps null: false
    end
    add_index :reviews, :user_id
    add_index :reviews, :product_id
    add_index :reviews, :order_item_id, unique: true
    add_foreign_key :reviews, :users, on_delete: :restrict
    add_foreign_key :reviews, :products, on_delete: :restrict
    add_foreign_key :reviews, :order_items, on_delete: :restrict
    add_check_constraint :reviews, 'rating >= 1 AND rating <= 5', name: 'reviews_rating_range'
  end
end
