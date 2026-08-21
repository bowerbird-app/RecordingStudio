# frozen_string_literal: true

require "test_helper"

class CapabilitiesIncludeForTest < Minitest::Test
  module Probe
    HostType = Class.new
    OtherType = Class.new
  end

  def setup
    @original_registered_capabilities = RecordingStudio.registered_capabilities.transform_values(&:dup)
    @original_capabilities =
      RecordingStudio.configuration.instance_variable_get(:@capabilities).transform_values(&:dup)
    @original_capability_options = RecordingStudio.configuration.instance_variable_get(:@capability_options).dup
    RecordingStudio.instance_variable_set(:@registered_capabilities, {})
    RecordingStudio.configuration.instance_variable_set(:@capabilities, {})
    RecordingStudio.configuration.instance_variable_set(:@capability_options, {})
  end

  def teardown
    RecordingStudio.instance_variable_set(:@registered_capabilities, @original_registered_capabilities)
    RecordingStudio.configuration.instance_variable_set(:@capabilities, @original_capabilities)
    RecordingStudio.configuration.instance_variable_set(:@capability_options, @original_capability_options)
  end

  def test_include_for_lives_on_capabilities_not_capability_concern
    assert_respond_to RecordingStudio::Capabilities, :include_for
    refute_respond_to RecordingStudio::Capability, :include_for
    refute_includes RecordingStudio::Recording.instance_methods, :include_for
    assert_equal RecordingStudio::Capabilities.singleton_class,
                 RecordingStudio::Capabilities.method(:include_for).owner
  end

  def test_include_for_returns_a_module_without_enabling
    mixin = RecordingStudio::Capabilities.include_for(:include_for_probe, flavor: "vanilla")

    assert_kind_of Module, mixin
    refute RecordingStudio.capability_enabled?(:include_for_probe, for: Probe::HostType)
    assert_nil RecordingStudio.capability_options(:include_for_probe, for: Probe::HostType)
  end

  def test_including_the_factory_module_enables_capability_and_sets_options
    Probe::HostType.include(
      RecordingStudio::Capabilities.include_for(:include_for_probe, flavor: "vanilla", servings: 2)
    )

    assert RecordingStudio.capability_enabled?(:include_for_probe, for: Probe::HostType)
    assert_equal({ flavor: "vanilla", servings: 2 },
                 RecordingStudio.capability_options(:include_for_probe, for: Probe::HostType))
    refute RecordingStudio.capability_enabled?(:include_for_probe, for: Probe::OtherType)
    assert_equal [:include_for_probe], RecordingStudio.capabilities_for(Probe::HostType)
    assert_equal [], RecordingStudio.capabilities_for(Probe::OtherType)
  end

  def test_include_for_sets_empty_options_when_none_are_passed
    Probe::HostType.include(RecordingStudio::Capabilities.include_for(:include_for_probe))

    assert RecordingStudio.capability_enabled?(:include_for_probe, for: Probe::HostType)
    assert_equal({}, RecordingStudio.capability_options(:include_for_probe, for: Probe::HostType))
  end

  def test_include_for_does_not_register_the_capability
    Probe::HostType.include(RecordingStudio::Capabilities.include_for(:include_for_probe, flavor: "vanilla"))

    refute RecordingStudio.registered_capabilities.key?(:include_for_probe)
    assert_empty RecordingStudio.registered_capabilities
  end

  def test_include_for_does_not_require_prior_registration
    RecordingStudio.register_capability(:unrelated_probe, source: "recording_studio_test_probe")

    Probe::HostType.include(RecordingStudio::Capabilities.include_for(:include_for_probe, flavor: "vanilla"))

    assert RecordingStudio.capability_enabled?(:include_for_probe, for: Probe::HostType)
    refute RecordingStudio.registered_capabilities.key?(:include_for_probe)
    assert RecordingStudio.registered_capabilities.key?(:unrelated_probe)
  end

  def test_include_for_yields_the_including_class_on_include
    yielded = nil
    ran_before_include = false
    mixin = RecordingStudio::Capabilities.include_for(:include_for_probe, flavor: "vanilla") do |base|
      ran_before_include = true
      yielded = base
    end

    refute ran_before_include

    Probe::HostType.include(mixin)

    assert_equal Probe::HostType, yielded
  end

  def test_mixin_to_wrapper_can_delegate_to_include_for
    wrapper = Module.new do
      def self.to(**options)
        RecordingStudio::Capabilities.include_for(:include_for_probe, **options)
      end
    end

    Probe::HostType.include(wrapper.to(flavor: "mint"))

    assert RecordingStudio.capability_enabled?(:include_for_probe, for: Probe::HostType)
    assert_equal({ flavor: "mint" }, RecordingStudio.capability_options(:include_for_probe, for: Probe::HostType))
    refute RecordingStudio.registered_capabilities.key?(:include_for_probe)
  end

  def test_include_for_rejects_blank_capability_names_on_include
    error = assert_raises(ArgumentError) do
      Probe::HostType.include(RecordingStudio::Capabilities.include_for("  "))
    end

    assert_match(/capability is required/, error.message)
  end

  def test_include_for_rejects_anonymous_including_classes
    anonymous = Class.new
    error = assert_raises(ArgumentError) do
      anonymous.include(RecordingStudio::Capabilities.include_for(:include_for_probe))
    end

    assert_match(/recordable type is required/, error.message)
  end
end
