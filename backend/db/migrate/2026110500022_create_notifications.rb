class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications, force: true do |t|
      t.bigint :user_id, null: false
      t.string :type, null: false, limit: 50
      t.string :title, null: false, limit: 180
      t.text :message, null: false
      t.text :data
      t.datetime :read_at
      t.timestamps null: false
    end
    add_index :notifications, :user_id
    add_index :notifications, :read_at
    add_foreign_key :notifications, :users, on_delete: :restrict
  end
end
