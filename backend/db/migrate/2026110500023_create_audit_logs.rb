class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs, force: true do |t|
      t.bigint :user_id
      t.string :action, null: false, limit: 120
      t.string :resource_type, null: false, limit: 80
      t.string :resource_id, limit: 120
      t.string :ip_address, limit: 45
      t.text :user_agent
      t.text :metadata
      t.timestamps null: false
    end
    add_index :audit_logs, :user_id
    add_index :audit_logs, :resource_type
    add_index :audit_logs, :action
    add_foreign_key :audit_logs, :users, on_delete: :restrict
  end
end
