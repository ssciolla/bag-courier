require "minitest/test_task"

Minitest::TestTask.create

task default: :test

namespace :db do
  desc "Run migrations"
  task :migrate, [:version] do |t, args|
    require "sequel/core"
    require_relative "db/database_error"
    require_relative "lib/config"

    Sequel.extension :migration

    config = Config::ConfigService.from_file(
      File.join(".", "config", "config.yml")
    )
    db_config = config.database
    if !db_config
      raise DatabaseError, "Migration failed. A database connection is not configured."
    end

    version = args[:version].to_i if args[:version]
    Sequel.connect(
      adapter: "mysql2",
      host: db_config.host,
      port: db_config.port,
      database: db_config.database,
      user: db_config.user,
      password: db_config.password,
      fractional_seconds: true
    ) do |db|
      Sequel::Migrator.run(db, "db/migrations", target: version)
    end
  end
end
