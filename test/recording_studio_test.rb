# frozen_string_literal: true

require "test_helper"

class RecordingStudioTest < Minitest::Test
  def setup
    @original_app_name = RecordingStudio.configuration.app_name
    RecordingStudio.configuration.app_name = "RecordingStudio"
    @original_registered_capabilities = RecordingStudio.registered_capabilities.transform_values(&:dup)
    @original_capabilities =
      RecordingStudio.configuration.instance_variable_get(:@capabilities).transform_values(&:dup)
    @original_capability_options = RecordingStudio.configuration.instance_variable_get(:@capability_options).dup
    RecordingStudio.instance_variable_set(:@registered_capabilities, {})
    RecordingStudio.configuration.instance_variable_set(:@capabilities, {})
    RecordingStudio.configuration.instance_variable_set(:@capability_options, {})
  end

  def teardown
    RecordingStudio.configuration.app_name = @original_app_name
    RecordingStudio.instance_variable_set(:@registered_capabilities, @original_registered_capabilities)
    RecordingStudio.configuration.instance_variable_set(:@capabilities, @original_capabilities)
    RecordingStudio.configuration.instance_variable_set(:@capability_options, @original_capability_options)
  end

  def test_version_exists
    assert_not_nil ::RecordingStudio::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::RecordingStudio::Engine
  end

  def test_app_name_configuration_default
    assert_equal "RecordingStudio", RecordingStudio.configuration.app_name
  end

  def test_app_name_configuration_configured
    original = RecordingStudio.configuration.app_name
    RecordingStudio.configure { |c| c.app_name = "My Custom App" }
    assert_equal "My Custom App", RecordingStudio.configuration.app_name
  ensure
    RecordingStudio.configuration.app_name = original
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
    registration = RecordingStudio.registered_capabilities.fetch(:auto_apply_probe)

    assert_equal capability_module, registration.fetch(:mod)
    assert_equal capability_module, registration.fetch(:recording_methods)
    assert_nil registration.fetch(:source)
    assert_equal [], registration.fetch(:child_recordables)
  end

  def test_register_capability_allows_child_recordables_without_recording_methods
    RecordingStudio.register_capability(
      :commentable_probe,
      source: "recording_studio_test_probe",
      child_recordables: "RecordingStudioComment"
    )

    registration = RecordingStudio.registered_capabilities.fetch(:commentable_probe)

    assert_nil registration[:mod]
    assert_nil registration[:recording_methods]
    assert_equal "recording_studio_test_probe", registration[:source]
    assert_equal ["RecordingStudioComment"], registration[:child_recordables]
  end

  def test_register_capability_refreshes_recording_methods_for_same_source
    first_module = Module.new
    second_module = Module.new do
      def capability_refresh_probe_value
        :refreshed
      end
    end

    RecordingStudio.register_capability(:refresh_probe, first_module, source: "recording_studio_test_probe")
    RecordingStudio.register_capability(:refresh_probe, second_module, source: "recording_studio_test_probe")

    registration = RecordingStudio.registered_capabilities.fetch(:refresh_probe)
    assert_equal second_module, registration.fetch(:mod)
    assert_equal second_module, registration.fetch(:recording_methods)
    assert RecordingStudio::Recording.included_modules.include?(second_module)
    assert_equal :refreshed, RecordingStudio::Recording.new.capability_refresh_probe_value
  end

  def test_register_capability_accepts_recording_methods_keyword
    capability_module = Module.new

    RecordingStudio.register_capability(
      :keyword_probe,
      recording_methods: capability_module,
      source: "recording_studio_test_probe"
    )

    registration = RecordingStudio.registered_capabilities.fetch(:keyword_probe)
    assert_equal capability_module, registration.fetch(:recording_methods)
    assert_equal "recording_studio_test_probe", registration.fetch(:source)
  end

  def test_capability_parent_types_follow_enablement_after_registration
    RecordingStudio.register_capability(
      :commentable_probe,
      source: "recording_studio_test_probe",
      child_recordables: "RecordingStudioComment"
    )

    assert_equal [], RecordingStudio.capability_parent_types_for("RecordingStudioComment")

    RecordingStudio.enable_capability(:commentable_probe, on: "RecordingStudioFolder")

    assert_equal ["RecordingStudioFolder"], RecordingStudio.capability_parent_types_for("RecordingStudioComment")
    assert_equal ["RecordingStudioComment"], RecordingStudio.child_recordable_types_for("RecordingStudioFolder")
    assert_equal [:commentable_probe],
                 RecordingStudio.parent_capabilities_for(
                   child_type: "RecordingStudioComment",
                   parent_type: "RecordingStudioFolder"
                 )
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
