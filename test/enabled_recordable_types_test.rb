# frozen_string_literal: true

require "test_helper"

class EnabledRecordableTypesTest < Minitest::Test
  PROBE_NAME = "CapabilityPreloadProbe"
  PROBE_FILE = File.expand_path("support/capability_preload_probe.rb", __dir__)

  def setup
    @original_types = RecordingStudio.configuration.recordable_types.dup
    @original_capabilities =
      RecordingStudio.configuration.instance_variable_get(:@capabilities).transform_values(&:dup)
    @original_capability_options = RecordingStudio.configuration.instance_variable_get(:@capability_options).dup
    @original_loaded =
      RecordingStudio::RecordableDeclarations.instance_variable_get(:@loaded_configured_type_names).dup

    unload_probe!
    Object.autoload(:CapabilityPreloadProbe, PROBE_FILE)
    RecordingStudio.configuration.recordable_types = @original_types + [PROBE_NAME]
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.instance_variable_set(:@capabilities, @original_capabilities)
    RecordingStudio.configuration.instance_variable_set(:@capability_options, @original_capability_options)
    RecordingStudio::RecordableDeclarations.instance_variable_set(
      :@loaded_configured_type_names,
      @original_loaded
    )
  end

  def test_enabled_recordable_types_for_returns_a_configured_type_before_its_class_loads
    assert_equal PROBE_FILE, Object.autoload?(:CapabilityPreloadProbe)
    refute RecordingStudio.capability_enabled?(:preload_probe, for: PROBE_NAME)

    enabled = RecordingStudio.configuration.enabled_recordable_types_for(:preload_probe)

    assert_includes enabled, PROBE_NAME
    assert_equal enabled, RecordingStudio.configuration.enabled_recordable_types_for(:preload_probe)
  end

  private

  def unload_probe!
    RecordingStudio::RecordableDeclarations
      .instance_variable_get(:@loaded_configured_type_names)
      .delete(PROBE_NAME)
    RecordingStudio.configuration.instance_variable_get(:@capabilities).delete(PROBE_NAME)
    options = RecordingStudio.configuration.instance_variable_get(:@capability_options)
    options.delete_if { |key, _value| key.last == PROBE_NAME }
    Object.send(:remove_const, :CapabilityPreloadProbe) if Object.const_defined?(:CapabilityPreloadProbe, false)
  end
end
