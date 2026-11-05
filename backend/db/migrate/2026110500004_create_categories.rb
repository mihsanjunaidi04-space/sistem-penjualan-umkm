class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories, force: true do |t|
      t.string :name, null: false, limit: 150
      t.string :slug, null: false, limit: 120
      t.text :description
      t.boolean :is_active, null: false, default: true
      t.timestamps null: false
    end
    add_index :categories, :slug, unique: true
  end
end
