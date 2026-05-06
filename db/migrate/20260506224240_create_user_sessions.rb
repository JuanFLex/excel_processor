class CreateUserSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer  :duration_seconds
      t.string   :ip_address
      t.string   :user_agent
      t.string   :sign_out_reason # 'manual', 'timeout', 'orphaned', 'forced'
      t.timestamps
    end

    add_index :user_sessions, [:user_id, :started_at]
    add_index :user_sessions, :ended_at
    add_index :user_sessions, :started_at
  end
end
