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
    config.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]

    previous = Rails.application.config.x.recording_studio
    Rails.application.config.x.recording_studio = config

    initializer = RecordingStudio::Engine.initializers.find { |init| init.name == "recording_studio.load_config" }
    initializer.run(Rails.application)

    assert_equal %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ], RecordingStudio.configuration.recordable_types
  ensure
    RecordingStudio.configuration.recordable_types = original
    Rails.application.config.x.recording_studio = previous
  end

  def test_load_config_handles_config_for_errors
    app = Rails.application
    original_method = app.method(:config_for)
    write_recording_studio_yaml("#{Rails.env}:\n  recordable_types: []\n")
    def app.config_for(_name)
      raise "boom"
    end

    initializer = RecordingStudio::Engine.initializers.find { |init| init.name == "recording_studio.load_config" }
    io = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(io)

    initializer.run(app)

    output = io.string
    assert_includes output, "config_for(:recording_studio)"
    assert_includes output, "RuntimeError"
    assert_includes output, "boom"
  ensure
    Rails.logger = original_logger if defined?(original_logger)
    app.singleton_class.send(:define_method, :config_for, original_method)
    remove_recording_studio_yaml
  end

  def test_load_config_is_silent_when_yaml_file_is_missing
    remove_recording_studio_yaml
    refute Rails.root.join("config/recording_studio.yml").exist?

    io = capture_load_config_log

    refute_includes io.string, "[RecordingStudio] Could not"
  end

  def test_load_config_warns_when_yaml_file_is_malformed
    write_recording_studio_yaml("{ this is not: [valid yaml")

    io = capture_load_config_log

    output = io.string
    assert_includes output, "config_for(:recording_studio)"
    assert_match(/Psych::|YAML|syntax/i, output)
  ensure
    remove_recording_studio_yaml
  end

  def test_load_config_warns_when_config_x_hash_fails
    xcfg = Object.new
    def xcfg.each_pair
      raise "x boom"
    end

    previous = Rails.application.config.x.recording_studio
    Rails.application.config.x.recording_studio = xcfg

    io = capture_load_config_log

    output = io.string
    assert_includes output, "config.x.recording_studio"
    assert_includes output, "RuntimeError"
    assert_includes output, "x boom"
  ensure
    Rails.application.config.x.recording_studio = previous
  end

  def test_load_config_warns_when_yaml_merge_fails
    write_recording_studio_yaml("#{Rails.env}:\n  recordable_types: []\n")
    configuration = RecordingStudio.configuration
    original_merge = configuration.method(:merge!)
    raised = false
    configuration.define_singleton_method(:merge!) do |*args, **kwargs, &block|
      unless raised
        raised = true
        raise "merge boom"
      end

      original_merge.call(*args, **kwargs, &block)
    end

    io = capture_load_config_log

    output = io.string
    assert_includes output, "Could not apply"
    assert_includes output, "RuntimeError"
    assert_includes output, "merge boom"
  ensure
    configuration.singleton_class.send(:remove_method, :merge!)
    remove_recording_studio_yaml
  end

  private

  def recording_studio_yaml_path
    Rails.root.join("config/recording_studio.yml")
  end

  def write_recording_studio_yaml(contents)
    File.write(recording_studio_yaml_path, contents)
  end

  def remove_recording_studio_yaml
    FileUtils.rm_f(recording_studio_yaml_path)
  end

  def capture_load_config_log
    initializer = RecordingStudio::Engine.initializers.find { |init| init.name == "recording_studio.load_config" }
    io = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(io)
    initializer.run(Rails.application)
    io
  ensure
    Rails.logger = original_logger
  end
end
