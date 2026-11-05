class CreateStoreSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :store_settings, force: true do |t|
      t.string :setting_key, null: false, limit: 120
      t.text :setting_value, null: false
      t.bigint :updated_by
      t.timestamps null: false
    end
    add_index :store_settings, :setting_key, unique: true
    add_index :store_settings, :updated_by
    add_foreign_key :store_settings, :users, column: :updated_by, primary_key: :id, on_delete: :restrict
  end
end
