# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RecordingStudio
  module Generators
    # Writes a partial unique index for recordables declared single under every parent.
    #
    #   rails generate recording_studio:single_child_index
    #
    # The WHERE clause is fixed from the declarations loaded in this process.
    class SingleChildIndexGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Create a partial unique index for single-child recordings"

      def write_single_child_index
        migration_template(
          "migration.rb.tt",
          "db/migrate/add_recording_studio_single_child_index.rb"
        )
      end

      private

      def index_name
        RecordingStudio::SingleChildren::INDEX_NAME
      end

      def where_sql
        RecordingStudio::SingleChildren.index_where_sql
      end

      def pairwise_lines
        RecordingStudio::SingleChildren.pairwise_lines
      end

      def migration_version
        ActiveRecord::Migration.current_version
      end
    end
  end
end
