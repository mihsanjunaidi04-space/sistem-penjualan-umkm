class CreateAuthRateLimitCounters < ActiveRecord::Migration[8.1]
  def change
    create_table :auth_rate_limit_counters do |t|
      t.string :key, null: false, limit: 160
      t.integer :count, null: false, default: 0
      t.datetime :window_started_at, null: false
      t.datetime :expires_at, null: false
      t.timestamps null: false
    end

    add_index :auth_rate_limit_counters, :key, unique: true
    add_index :auth_rate_limit_counters, :expires_at
    add_check_constraint :auth_rate_limit_counters, "count >= 0", name: "auth_rate_limit_counters_count_non_negative"
  end
end
