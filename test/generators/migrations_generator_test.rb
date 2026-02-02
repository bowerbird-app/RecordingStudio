# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/recording_studio/migrations/migrations_generator"

class MigrationsGeneratorTest < Rails::Generators::TestCase
  tests RecordingStudio::Generators::MigrationsGenerator
  destination File.expand_path("../tmp/migrations_generator", __dir__)

  def setup
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "db/migrate"))
  end

  def test_copies_engine_migrations
    run_generator

    migration_files = Dir.glob(File.join(destination_root, "db/migrate", "*_create_recording_studio_recordings.rb"))
    assert_equal 1, migration_files.size
  end

  def test_skips_existing_migration_when_option_enabled
    existing = File.join(destination_root, "db/migrate", "20200101010101_create_recording_studio_recordings.rb")
    File.write(existing, "# existing migration")

    run_generator

    migration_files = Dir.glob(File.join(destination_root, "db/migrate", "*_create_recording_studio_recordings.rb"))
    assert_equal 1, migration_files.size
  end
end
