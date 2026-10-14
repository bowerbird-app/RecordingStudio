# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RecordingStudio
  module Generators
    # Shared migrations install generator for Recording Studio addon gems.
    #
    # Matches the gem_template / majority-addon generator: copies
    # `db/migrate/*.rb` from the gem root into the host app with fresh
    # timestamps, optionally skipping migrations that already exist by name.
    #
    # @example
    #   module GemTemplate
    #     module Generators
    #       class MigrationsGenerator < RecordingStudio::Generators::MigrationsGeneratorBase
    #         source_root File.expand_path("../../../..", __dir__)
    #         self.engine_label = "GemTemplate"
    #         desc "Copy GemTemplate migrations to your application"
    #       end
    #     end
    #   end
    class MigrationsGeneratorBase < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      class_option :skip_existing, type: :boolean, default: true,
                                   desc: "Skip migrations that already exist (based on name, ignoring timestamp)"

      class << self
        attr_accessor :engine_label
      end

      def copy_migrations
        migration_files = listed_migration_files
        return if migration_files.nil?

        say "Found #{migration_files.size} migration(s) to install:", :green
        copy_migration_files(migration_files)
        say "\nRun 'bin/rails db:migrate' to apply the migrations.", :green
      end

      private

      def engine_label
        self.class.engine_label.presence || "RecordingStudio"
      end

      def migrations_directory
        File.join(self.class.source_root, "db", "migrate")
      end

      def listed_migration_files
        migrations_dir = migrations_directory
        return missing_migrations_warning unless File.directory?(migrations_dir)

        migration_files = Dir.glob(File.join(migrations_dir, "*.rb"))
        return missing_migrations_warning if migration_files.empty?

        migration_files
      end

      def missing_migrations_warning
        say "No migrations found in #{engine_label} engine.", :yellow
        nil
      end

      def copy_migration_files(source_paths)
        source_paths.each { |source_path| copy_one_migration(source_path) }
      end

      def copy_one_migration(source_path)
        migration_name = File.basename(source_path).sub(/^\d+_/, "")
        if options[:skip_existing] && migration_exists?(migration_name)
          say "  skip  #{migration_name} (already exists)", :yellow
          return
        end

        destination_path = File.join("db/migrate", "#{next_migration_number}_#{migration_name}")
        copy_file source_path, destination_path
        say "  create  #{destination_path}", :green
        sleep 0.1
      end

      def migration_exists?(migration_name)
        Dir.glob(File.join(destination_root, "db/migrate", "*_#{migration_name}")).any?
      end

      def next_migration_number
        ActiveRecord::Migration.next_migration_number(
          Time.now.utc.strftime("%Y%m%d%H%M%S")
        )
      end
    end
  end
end
