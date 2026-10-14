# frozen_string_literal: true

require "test_helper"

class AddonConfigurationTest < Minitest::Test
  class ExampleAddon
    class Configuration < RecordingStudio::AddonConfiguration
      attr_accessor :timeout, :api_key

      def initialize(hooks: nil)
        super
        @timeout = 5
        @api_key = nil
      end

      def to_h
        {
          timeout: timeout,
          api_key: api_key,
          hooks_registered: hooks_registered
        }
      end
    end

    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration) if block_given?
      end
    end
  end

  def setup
    ExampleAddon.instance_variable_set(:@configuration, nil)
  end

  def test_defaults_include_hooks_registry
    config = ExampleAddon::Configuration.new

    assert_kind_of RecordingStudio::Hooks, config.hooks
    assert_equal 5, config.timeout
    assert_equal({}, config.hooks_registered)
  end

  def test_merge_applies_known_setters
    config = ExampleAddon::Configuration.new
    config.merge!(timeout: 12, api_key: "secret", unknown: "ignored")

    assert_equal 12, config.timeout
    assert_equal "secret", config.api_key
  end

  def test_hooks_registered_counts_registered_events
    config = ExampleAddon::Configuration.new
    config.hooks.before_service { "ok" }
    config.hooks.after_initialize { "ok" }

    assert_equal 1, config.hooks_registered[:before_service]
    assert_equal 1, config.hooks_registered[:after_initialize]
  end

  def test_to_h_includes_hooks_registered
    ExampleAddon.configure do |config|
      config.timeout = 9
      config.hooks.on(:custom) { true }
    end

    summary = ExampleAddon.configuration.to_h
    assert_equal 9, summary[:timeout]
    assert_equal 1, summary[:hooks_registered][:custom]
  end

  def test_custom_hooks_instance_can_be_injected
    custom_hooks = RecordingStudio::Hooks.new
    config = ExampleAddon::Configuration.new(hooks: custom_hooks)

    assert_same custom_hooks, config.hooks
  end
end
