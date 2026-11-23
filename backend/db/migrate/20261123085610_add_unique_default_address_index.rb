class AddUniqueDefaultAddressIndex < ActiveRecord::Migration[8.1]
  def up
    # First, ensure data integrity by removing duplicate defaults per user
    # Keep the most recent default address (highest id), unset others
    execute <<-SQL
      WITH ranked AS (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY id DESC) as rn
        FROM addresses
        WHERE is_default = true
      )
      UPDATE addresses
      SET is_default = false
      WHERE id IN (
        SELECT id FROM ranked WHERE rn > 1
      )
    SQL

    # Add unique partial index: one default address per user
    add_index :addresses, :user_id, unique: true, where: "is_default = true", name: "index_addresses_on_user_id_unique_default"
  end

  def down
    # This rollback is structural only. The normalized is_default values cannot
    # be restored because the previous duplicate-default values were not stored.
    remove_index :addresses, name: "index_addresses_on_user_id_unique_default"
  end
end
