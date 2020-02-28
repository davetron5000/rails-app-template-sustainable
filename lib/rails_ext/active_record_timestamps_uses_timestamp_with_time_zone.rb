require "active_record/connection_adapters/postgresql_adapter.rb"

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::NATIVE_DATABASE_TYPES[:datetime] = {
  name: "timestamptz"
}
