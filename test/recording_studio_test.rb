# frozen_string_literal: true

require "test_helper"

class RecordingStudioTest < Minitest::Test
  def setup
    @original_registered_capabilities = RecordingStudio.registered_capabilities.dup
  end

  def teardown
    RecordingStudio.instance_variable_set(:@registered_capabilities, @original_registered_capabilities)
  end

  def test_version_exists
    assert_not_nil ::RecordingStudio::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::RecordingStudio::Engine
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

  def test_configuration_to_h_excludes_removed_feature_flags
    refute_includes RecordingStudio.configuration.to_h.keys, :features
  end

  def test_configuration_to_h_reports_registered_hook_counts
    RecordingStudio.configuration.hooks.after_initialize {}

    assert_equal 1, RecordingStudio.configuration.to_h.fetch(:hooks_registered).fetch(:after_initialize)
  ensure
    RecordingStudio.configuration.hooks.clear!
  end
end
