# frozen_string_literal: true

require "test_helper"
require "stringio"

class RecordingStudioTest < Minitest::Test
  def setup
    @original_features = RecordingStudio.features.to_h
    @original_registered_capabilities = RecordingStudio.registered_capabilities.dup
    RecordingStudio.reset_runtime_warnings!
  end

  def teardown
    @original_features.each do |feature_name, value|
      RecordingStudio.features.public_send("#{feature_name}=", value)
    end
    RecordingStudio.instance_variable_set(:@registered_capabilities, @original_registered_capabilities)
  end

  def test_version_exists
    assert_not_nil ::RecordingStudio::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::RecordingStudio::Engine
  end

  def test_feature_toggles_default_to_true
    assert RecordingStudio.features.device_sessions?
  end

  def test_feature_toggles_are_independent
    RecordingStudio.configure do |config|
      config.features.device_sessions = false
    end

    assert_not RecordingStudio.features.device_sessions?
  end

  def test_feature_toggles_cast_common_string_values
    RecordingStudio.configure do |config|
      config.features.device_sessions = "0"
    end

    assert_not RecordingStudio.features.device_sessions?
  end

  def test_register_capability_applies_capability_without_manual_apply
    capability_module = Module.new do
      def capability_auto_apply_probe_value
        :ok
      end
    end

    RecordingStudio.register_capability(:auto_apply_probe, capability_module)
    RecordingStudio.register_capability(:auto_apply_probe, capability_module)

    assert_includes RecordingStudio::Recording.included_modules, capability_module
    assert RecordingStudio::Recording.new.respond_to?(:capability_auto_apply_probe_value)
    included_count = RecordingStudio::Recording.included_modules.count { |mod| mod == capability_module }
    assert_equal 1, included_count
    assert_equal capability_module, RecordingStudio.registered_capabilities.fetch(:auto_apply_probe).fetch(:mod)
  end

  def test_register_capability_works_without_legacy_gate
    capability_module = Module.new do
      def addon_copy_probe_value
        :ok
      end
    end

    RecordingStudio.register_capability(:copyable, capability_module)

    assert_includes RecordingStudio::Recording.included_modules, capability_module
    assert RecordingStudio::Recording.new.respond_to?(:addon_copy_probe_value)
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
