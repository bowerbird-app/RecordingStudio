# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "recording_studio/generators/migrations_generator_base"

class MigrationsGeneratorBaseTest < Rails::Generators::TestCase
  destination File.expand_path("../tmp/migrations_generator_base", __dir__)

  module ExampleAddon
    module Generators
      class MigrationsGenerator < RecordingStudio::Generators::MigrationsGeneratorBase
        source_root File.expand_path("fixture_engine", __dir__)
        self.engine_label = "ExampleAddon"
        desc "Copy ExampleAddon migrations to your application"
      end
    end
  end

  tests ExampleAddon::Generators::MigrationsGenerator

  def setup
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "db/migrate"))
    write_fixture_migrations
  end

  def teardown
    FileUtils.rm_rf(fixture_engine_root)
  end

  def test_copies_migrations_with_fresh_timestamps
    run_generator

    copied = Dir.glob(File.join(destination_root, "db/migrate", "*.rb"))
    assert_equal 2, copied.size

    names = copied.map { |path| File.basename(path).sub(/^\d+_/, "") }.sort
    assert_equal %w[create_example_addon_items.rb create_example_addon_pages.rb], names

    copied.each do |path|
      refute_match(/\A2025010100000/, File.basename(path))
    end
  end

  def test_skips_existing_migration_by_name
    existing = File.join(destination_root, "db/migrate", "20200101010101_create_example_addon_pages.rb")
    File.write(existing, "# existing")

    run_generator

    pages = Dir.glob(File.join(destination_root, "db/migrate", "*_create_example_addon_pages.rb"))
    items = Dir.glob(File.join(destination_root, "db/migrate", "*_create_example_addon_items.rb"))
    assert_equal 1, pages.size
    assert_equal 1, items.size
    assert_equal "# existing", File.read(pages.first)
  end

  def test_reports_when_no_migrations_directory
    FileUtils.rm_rf(File.join(fixture_engine_root, "db"))

    run_generator
    assert_empty Dir.glob(File.join(destination_root, "db/migrate", "*_create_example_addon_*.rb"))
  end

  private

  def fixture_engine_root
    File.join(__dir__, "fixture_engine")
  end

  def write_fixture_migrations
    migrate_dir = File.join(fixture_engine_root, "db", "migrate")
    FileUtils.mkdir_p(migrate_dir)
    File.write(File.join(migrate_dir, "20250101000001_create_example_addon_pages.rb"), "# pages\n")
    File.write(File.join(migrate_dir, "20250101000002_create_example_addon_items.rb"), "# items\n")
  end
end
