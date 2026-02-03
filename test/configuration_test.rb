# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def test_default_configuration_values
    config = RecordingStudio::Configuration.new

    assert_equal [], config.recordable_types
    assert_nil config.impersonator.call
    assert config.event_notifications_enabled
    assert_equal :return_existing, config.idempotency_mode
    assert_equal :dup, config.recordable_dup_strategy
  end

  def test_recordable_types_normalization
    config = RecordingStudio::Configuration.new
    config.recordable_types = ["Page", :Page]

    assert_equal ["Page"], config.recordable_types
  end

  def test_instrumentation_enabled_alias
    config = RecordingStudio::Configuration.new

    config.instrumentation_enabled = false

    refute config.event_notifications_enabled
    refute config.instrumentation_enabled
  end

  def test_merge_ignores_unknown_keys
    config = RecordingStudio::Configuration.new

    config.merge!(unknown: "value", idempotency_mode: :raise)

    assert_equal :raise, config.idempotency_mode
    refute config.respond_to?(:unknown)
  end

  def test_to_h_includes_hook_counts
    config = RecordingStudio::Configuration.new
    config.hooks.before_initialize { nil }

    result = config.to_h

    assert_equal 1, result[:hooks_registered][:before_initialize]
  end

  def test_register_recordable_type_updates_configuration
    original = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = []

    RecordingStudio.register_recordable_type("Page")

    assert_includes RecordingStudio.configuration.recordable_types, "Page"
  ensure
    RecordingStudio.configuration.recordable_types = original
  end
end
