# frozen_string_literal: true

Rails.application.config.paths["db/migrate"] = [
  Rails.root.join("db/migrate_app"),
  ControlRoom::Engine.root.join("db/migrate")
]

if defined?(ActiveRecord::Migrator)
  ActiveRecord::Migrator.migrations_paths = Rails.application.config.paths["db/migrate"].to_a
end
