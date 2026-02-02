# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/recording_studio/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests RecordingStudio::Generators::InstallGenerator
  destination File.expand_path("../tmp/install_generator", __dir__)

  def setup
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config/initializers"))
    FileUtils.mkdir_p(File.join(destination_root, "db/migrate"))
    File.write(File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  def test_installs_routes_and_initializer
    generator_class = RecordingStudio::Generators::InstallGenerator
    original_yes = generator_class.instance_method(:yes?)

    generator_class.define_method(:yes?) { |_message| false }
    run_generator

    assert_file "config/routes.rb", /mount RecordingStudio::Engine/
    assert_file "config/initializers/recording_studio.rb"
  ensure
    generator_class.define_method(:yes?, original_yes)
  end
end
