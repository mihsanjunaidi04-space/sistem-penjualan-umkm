class CreateProductImages < ActiveRecord::Migration[8.1]
  def change
    create_table :product_images, force: true do |t|
      t.bigint :product_id, null: false
      t.string :storage_key, null: false
      t.string :alt_text, limit: 180
      t.integer :position, null: false, default: 0
      t.timestamps null: false
    end
    add_index :product_images, :product_id
    add_foreign_key :product_images, :products, on_delete: :restrict
    add_check_constraint :product_images, 'position >= 0', name: 'product_images_position_non_negative'
  end
end
