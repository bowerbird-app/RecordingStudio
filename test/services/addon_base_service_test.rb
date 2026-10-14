# frozen_string_literal: true

require "test_helper"

module RecordingStudio
  module Services
    class AddonBaseServiceTest < Minitest::Test
      module ExampleAddon
        class << self
          def configuration
            @configuration ||= RecordingStudio::AddonConfiguration.new
          end
        end

        class EchoService < AddonBaseService
          self.hooks_owner = ExampleAddon

          def initialize(message:)
            @message = message
          end

          private

          def perform
            success(@message)
          end

          def service_args
            { message: @message }
          end
        end

        class FailingService < AddonBaseService
          self.hooks_owner = ExampleAddon

          private

          def perform
            failure("nope", value: { kept: true })
          end
        end
      end

      def setup
        ExampleAddon.instance_variable_set(:@configuration, nil)
        RecordingStudio.configuration.hooks.clear!
      end

      def teardown
        ExampleAddon.configuration.hooks.clear!
        RecordingStudio.configuration.hooks.clear!
      end

      def test_runs_hooks_on_addon_configuration_not_core
        addon_hooks = ExampleAddon.configuration.hooks
        core_hooks = RecordingStudio.configuration.hooks

        addon_before = nil
        core_before = nil
        addon_hooks.before_service { |klass, args| addon_before = [klass, args] }
        core_hooks.before_service { |klass, _args| core_before = klass }

        result = ExampleAddon::EchoService.call(message: "hi")

        assert result.success?
        assert_equal "hi", result.value
        assert_equal [ExampleAddon::EchoService, { message: "hi" }], addon_before
        assert_nil core_before
      end

      def test_around_hooks_wrap_perform_on_addon_registry
        events = []
        ExampleAddon.configuration.hooks.around_service do |_service, block|
          events << :before
          value = block.call
          events << :after
          value
        end

        result = ExampleAddon::EchoService.call(message: "wrapped")

        assert_equal "wrapped", result.value
        assert_equal %i[before after], events
      end

      def test_failure_can_retain_value_for_accessible_compatible_call_sites
        result = ExampleAddon::FailingService.call

        assert result.failure?
        assert_equal "nope", result.error
        assert_equal({ kept: true }, result.value)
      end
    end
  end
end
