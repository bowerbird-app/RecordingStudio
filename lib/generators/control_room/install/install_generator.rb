# frozen_string_literal: true

module ControlRoom
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs ControlRoom engine into your application"

      def mount_engine
        route 'mount ControlRoom::Engine, at: "/control_room"'
      end

      def copy_initializer
        template "control_room_initializer.rb", "config/initializers/control_room.rb"
      end

      def install_migrations
        invoke "control_room:migrations"
      end

      def add_yaml_config
        return unless yes?("Would you like to add `config/control_room.yml` for environment-specific settings? [y/N]")

        template "control_room.yml", "config/control_room.yml"
      end

      def add_tailwind_source
        tailwind_css_path = Rails.root.join("app/assets/tailwind/application.css")

        unless File.exist?(tailwind_css_path)
          say "Tailwind CSS not detected. Skipping Tailwind configuration.", :yellow
          say "If you use Tailwind, add this line to your Tailwind CSS config:", :yellow
          say '  @source "../../vendor/bundle/**/control_room/app/views/**/*.erb";', :yellow
          return
        end

        tailwind_content = File.read(tailwind_css_path)
        source_line = '@source "../../vendor/bundle/**/control_room/app/views/**/*.erb";'

        if tailwind_content.include?(source_line)
          say "Tailwind already configured to include ControlRoom views.", :green
          return
        end

        # Insert the @source directive after @import "tailwindcss";
        if tailwind_content.include?('@import "tailwindcss"')
          inject_into_file tailwind_css_path, after: "@import \"tailwindcss\";\n" do
            "\n/* Include ControlRoom engine views for Tailwind CSS */\n#{source_line}\n"
          end
          say "Added ControlRoom views to Tailwind CSS configuration.", :green
          say "Run 'bin/rails tailwindcss:build' to rebuild your CSS.", :green
        else
          say "Could not find @import \"tailwindcss\" in your Tailwind config.", :yellow
          say "Please manually add this line to your Tailwind CSS config:", :yellow
          say "  #{source_line}", :yellow
        end
      end

      def show_readme
        readme "INSTALL.md" if behavior == :invoke
      end
    end
  end
end
