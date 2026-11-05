class CreateAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :addresses, force: true do |t|
      t.bigint :user_id, null: false
      t.string :recipient_name, null: false, limit: 150
      t.string :phone, null: false, limit: 30
      t.text :address_line, null: false
      t.string :province, null: false, limit: 120
      t.string :city, null: false, limit: 120
      t.string :district, null: false, limit: 120
      t.string :postal_code, null: false, limit: 20
      t.text :notes
      t.boolean :is_default, null: false, default: false
      t.timestamps null: false
    end
    add_index :addresses, :user_id
    add_foreign_key :addresses, :users, on_delete: :restrict
  end
end
