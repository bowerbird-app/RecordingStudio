# frozen_string_literal: true

require "test_helper"
require "stringio"

class EngineInitializersTest < ActiveSupport::TestCase
  def setup
    RecordingStudio.configuration.hooks.clear!
    @original_features = RecordingStudio.features.to_h
    RecordingStudio.reset_runtime_warnings!
  end

  def teardown
    @original_features.each do |feature_name, value|
      RecordingStudio.features.public_send("#{feature_name}=", value)
    end
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
    config.recordable_types = ["RecordingStudioPage"]

    previous = Rails.application.config.x.recording_studio
    Rails.application.config.x.recording_studio = config

    initializer = RecordingStudio::Engine.initializers.find { |init| init.name == "recording_studio.load_config" }
    initializer.run(Rails.application)

    assert_equal ["RecordingStudioPage"], RecordingStudio.configuration.recordable_types
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

  def test_load_config_warns_when_move_addon_is_loaded_and_legacy_feature_enabled
    initializer = RecordingStudio::Engine.initializers.find { |init| init.name == "recording_studio.load_config" }
    Gem.loaded_specs["recording-studio-move"] = Gem::Specification.new

    warnings = capture_logger_warnings do
      initializer.run(Rails.application)
    end

    assert_includes warnings, "recording-studio-move"
    assert_includes warnings, "config.features.move = false"
  ensure
    Gem.loaded_specs.delete("recording-studio-move")
  end

  def test_load_config_warns_for_each_legacy_addon_conflict
    initializer = RecordingStudio::Engine.initializers.find { |init| init.name == "recording_studio.load_config" }
    %w[recording-studio-copy recording-studio-device-sessions].each do |gem_name|
      Gem.loaded_specs[gem_name] = Gem::Specification.new
    end

    warnings = capture_logger_warnings do
      initializer.run(Rails.application)
    end

    assert_includes warnings, "recording-studio-copy"
    assert_includes warnings, "config.features.copyable = false"
    assert_includes warnings, "recording-studio-device-sessions"
    assert_includes warnings, "config.features.device_sessions = false"
  ensure
    Gem.loaded_specs.delete("recording-studio-copy")
    Gem.loaded_specs.delete("recording-studio-device-sessions")
  end

  def test_load_config_does_not_warn_when_conflicting_legacy_feature_is_disabled
    initializer = RecordingStudio::Engine.initializers.find { |init| init.name == "recording_studio.load_config" }
    RecordingStudio.features.move = false
    Gem.loaded_specs["recording-studio-move"] = Gem::Specification.new

    warnings = capture_logger_warnings do
      initializer.run(Rails.application)
    end

    assert_equal "", warnings
  ensure
    Gem.loaded_specs.delete("recording-studio-move")
  end

  private

  def capture_logger_warnings
    original_logger = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io)
    Rails.logger.level = Logger::WARN
    yield
    io.string
  ensure
    Rails.logger = original_logger
  end
end
