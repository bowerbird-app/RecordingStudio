# frozen_string_literal: true

module RecordingStudio
  module Generators
    class ViewsGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Generates RecordingStudio scaffold view templates for a resource"

      def create_views
        template "index.html.erb.tt", File.join(resource_views_path, "index.html.erb")
        template "show.html.erb.tt", File.join(resource_views_path, "show.html.erb")
        template "new.html.erb.tt", File.join(resource_views_path, "new.html.erb")
        template "edit.html.erb.tt", File.join(resource_views_path, "edit.html.erb")
        template "_form.html.erb.tt", File.join(resource_views_path, "_form.html.erb")
      end

      private

      def resource_views_path
        File.join("app/views", plural_file_path)
      end

      def plural_file_path
        file_path.pluralize
      end

      def plural_route_helper
        plural_file_path.tr("/", "_")
      end

      def singular_route_helper
        file_path.tr("/", "_")
      end
    end
  end
end
