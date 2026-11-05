# frozen_string_literal: true

module SQLiteWalConfiguration
  def configure_connection
    super
    return unless adapter_name == 'SQLite'

    execute('PRAGMA journal_mode = WAL')
    execute('PRAGMA busy_timeout = 5000')
    execute('PRAGMA foreign_keys = ON')
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(SQLiteWalConfiguration)
end
