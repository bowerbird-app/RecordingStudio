# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def test_default_configuration_values
    config = RecordingStudio::Configuration.new

    assert_equal [], config.recordable_types
    assert config.event_notifications_enabled
    assert_equal :return_existing, config.idempotency_mode
    assert_equal :soft, config.unrecord_mode
    assert_equal :dup, config.recordable_dup_strategy
  end

  def test_recordable_types_normalization
    config = RecordingStudio::Configuration.new
    config.recordable_types = ["Page", :Page]

    assert_equal ["Page"], config.recordable_types
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
