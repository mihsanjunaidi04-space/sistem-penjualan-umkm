class CreateJwtRevocations < ActiveRecord::Migration[8.1]
  def change
    create_table :jwt_revocations do |t|
      t.string :jti, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :jwt_revocations, :jti, unique: true
    add_index :jwt_revocations, :expires_at
  end
end
