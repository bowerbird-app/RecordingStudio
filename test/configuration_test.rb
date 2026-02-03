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

  def test_default_actor_and_impersonator_use_current
    config = RecordingStudio::Configuration.new
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    impersonator = User.create!(name: "Admin", email: "admin@example.com", password: "password123")

    Current.actor = actor
    Current.impersonator = impersonator

    assert_equal actor, config.actor.call
    assert_equal impersonator, config.impersonator.call
  ensure
    Current.reset_all
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

  def test_merge_accepts_string_keys_and_nil
    config = RecordingStudio::Configuration.new

    config.merge!("idempotency_mode" => :raise)
    assert_equal :raise, config.idempotency_mode

    assert_nil config.merge!(nil)
  end

  def test_to_h_includes_hook_counts
    config = RecordingStudio::Configuration.new
    config.hooks.before_initialize { nil }

    result = config.to_h

    assert_equal 1, result[:hooks_registered][:before_initialize]
    assert_equal config.recordable_dup_strategy, result[:recordable_dup_strategy]
    assert_equal config.include_children, result[:include_children]
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
