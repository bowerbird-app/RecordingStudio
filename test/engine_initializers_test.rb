# frozen_string_literal: true

require "test_helper"

class EngineInitializersTest < ActiveSupport::TestCase
  def setup
    RecordingStudio.configuration.hooks.clear!
  end

  def test_before_initialize_hook_runs
    called = false
    RecordingStudio.configuration.hooks.before_initialize { called = true }

    initializer = RecordingStudio::Engine.initializers.find { |init| init.name == "recording_studio.before_initialize" }
    initializer.run(Rails.application)

    assert called
  end

  def test_after_initialize_hook_runs
    called = false
    RecordingStudio.configuration.hooks.after_initialize { called = true }

    initializer = RecordingStudio::Engine.initializers.find { |init| init.name == "recording_studio.after_initialize" }
    initializer.run(Rails.application)

    assert called
  end

  def test_on_configuration_merges_config_x
    original = RecordingStudio.configuration.recordable_types
    config = ActiveSupport::OrderedOptions.new
    config.recordable_types = ["Page"]

    previous = Rails.application.config.x.recording_studio
    Rails.application.config.x.recording_studio = config

    initializer = RecordingStudio::Engine.initializers.find { |init| init.name == "recording_studio.load_config" }
    initializer.run(Rails.application)

    assert_equal ["Page"], RecordingStudio.configuration.recordable_types
  ensure
    RecordingStudio.configuration.recordable_types = original
    Rails.application.config.x.recording_studio = previous
  end

  def test_load_config_handles_config_for_errors
    app = Rails.application
    original_method = app.method(:config_for)
    def app.config_for(_name)
      raise "boom"
    end

    initializer = RecordingStudio::Engine.initializers.find { |init| init.name == "recording_studio.load_config" }

    assert_silent do
      initializer.run(app)
    end
  ensure
    app.singleton_class.send(:define_method, :config_for, original_method)
  end
end
