# frozen_string_literal: true

require "test_helper"
require "stringio"

class RecordingStudioTest < Minitest::Test
  def setup
    @original_features = RecordingStudio.features.to_h
    RecordingStudio.reset_runtime_warnings!
  end

  def teardown
    @original_features.each do |feature_name, value|
      RecordingStudio.features.public_send("#{feature_name}=", value)
    end
  end

  def test_version_exists
    assert_not_nil ::RecordingStudio::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::RecordingStudio::Engine
  end

  def test_feature_toggles_default_to_true
    assert RecordingStudio.features.move?
    assert RecordingStudio.features.copyable?
    assert RecordingStudio.features.device_sessions?
  end

  def test_feature_toggles_are_independent
    RecordingStudio.configure do |config|
      config.features.move = false
      config.features.copyable = true
      config.features.device_sessions = false
    end

    assert_not RecordingStudio.features.move?
    assert RecordingStudio.features.copyable?
    assert_not RecordingStudio.features.device_sessions?
  end

  def test_feature_toggles_cast_common_string_values
    RecordingStudio.configure do |config|
      config.features.move = "false"
      config.features.copyable = "1"
      config.features.device_sessions = "0"
    end

    assert_not RecordingStudio.features.move?
    assert RecordingStudio.features.copyable?
    assert_not RecordingStudio.features.device_sessions?
  end

  def test_warn_legacy_feature_use_emits_once_per_feature
    warnings = capture_logger_warnings do
      RecordingStudio.warn_legacy_feature_use!(:move, used_by: "test")
      RecordingStudio.warn_legacy_feature_use!(:move, used_by: "test")
    end

    assert_includes warnings, "config.features.move = false"
    assert_equal 1, warnings.scan("Legacy built-in 'move' feature").size
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
