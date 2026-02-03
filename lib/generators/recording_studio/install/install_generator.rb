# frozen_string_literal: true

module RecordingStudio
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs RecordingStudio engine into your application"

      def mount_engine
        route 'mount RecordingStudio::Engine, at: "/recording_studio"'
      end

      def copy_initializer
        template "recording_studio_initializer.rb", "config/initializers/recording_studio.rb"
      end

      def install_migrations
        invoke "recording_studio:migrations"
      end

      def add_yaml_config
        unless yes?("Would you like to add `config/recording_studio.yml` for environment-specific settings? [y/N]")
          return
        end

        template "recording_studio.yml", "config/recording_studio.yml"
      end

      def add_tailwind_source
        tailwind_css_path = Rails.root.join("app/assets/tailwind/application.css")

        unless File.exist?(tailwind_css_path)
          say "Tailwind CSS not detected. Skipping Tailwind configuration.", :yellow
          say "If you use Tailwind, add this line to your Tailwind CSS config:", :yellow
          say '  @source "../../vendor/bundle/**/recording_studio/app/views/**/*.erb";', :yellow
          return
        end

        tailwind_content = File.read(tailwind_css_path)
        source_line = '@source "../../vendor/bundle/**/recording_studio/app/views/**/*.erb";'

        if tailwind_content.include?(source_line)
          say "Tailwind already configured to include RecordingStudio views.", :green
          return
        end

        # Insert the @source directive after @import "tailwindcss";
        if tailwind_content.include?('@import "tailwindcss"')
          inject_into_file tailwind_css_path, after: "@import \"tailwindcss\";\n" do
            "\n/* Include RecordingStudio engine views for Tailwind CSS */\n#{source_line}\n"
          end
          say "Added RecordingStudio views to Tailwind CSS configuration.", :green
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
