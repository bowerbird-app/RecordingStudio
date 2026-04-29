# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/recording_studio/migrations/migrations_generator"

class MigrationsGeneratorTest < Rails::Generators::TestCase
  tests RecordingStudio::Generators::MigrationsGenerator
  destination File.expand_path("../tmp/migrations_generator", __dir__)

  LEGACY_ACCESS_MIGRATIONS = %w[
    create_recording_studio_accesses.rb
    create_recording_studio_access_boundaries.rb
    create_recording_studio_device_sessions.rb
    remove_access_control_and_device_sessions.rb
  ].freeze

  def setup
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "db/migrate"))
  end

  def test_copies_fresh_install_migrations_only
    run_generator

    migration_files = Dir.glob(File.join(destination_root, "db/migrate", "*_create_recording_studio_recordings.rb"))
    assert_equal 1, migration_files.size

    copied_filenames = copied_migration_filenames

    LEGACY_ACCESS_MIGRATIONS.each do |migration_name|
      refute_includes copied_filenames, migration_name
    end
  end

  def test_skips_existing_migration_when_option_enabled
    existing = File.join(destination_root, "db/migrate", "20200101010101_create_recording_studio_recordings.rb")
    File.write(existing, "# existing migration")

    run_generator

    migration_files = Dir.glob(File.join(destination_root, "db/migrate", "*_create_recording_studio_recordings.rb"))
    assert_equal 1, migration_files.size
  end

  def test_full_history_option_copies_legacy_access_migrations
    run_generator(["--full_history"])

    copied_filenames = copied_migration_filenames

    LEGACY_ACCESS_MIGRATIONS.each do |migration_name|
      assert_includes copied_filenames, migration_name
    end
  end

  private

  def copied_migration_filenames
    Dir.glob(File.join(destination_root, "db/migrate", "*.rb")).map do |path|
      File.basename(path).sub(/^\d+_/, "")
    end
  end
end
