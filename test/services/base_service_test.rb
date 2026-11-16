# frozen_string_literal: true

require "test_helper"

module RecordingStudio
  module Services
    class BaseServiceTest < Minitest::Test
      # Test subclass for testing BaseService
      class TestService < BaseService
        def initialize(should_succeed:, value: nil, error: nil)
          @should_succeed = should_succeed
          @value = value
          @error = error
        end

        private

        def perform
          if @should_succeed
            success(@value)
          else
            failure(@error)
          end
        end
      end

      # Test subclass that doesn't implement perform
      class IncompleteService < BaseService
      end

      class HookedService < BaseService
        private

        def perform
          success("ok")
        end

        def service_args
          { payload: "data" }
        end
      end

      class RedactingService < BaseService
        def initialize(secret:)
          @secret = secret
        end

        private

        def perform
          success(@secret)
        end

        def hook_result(result)
          success("redacted:#{result.value}")
        end
      end

      class ClassHonestSubject
        def initialize(service)
          @service = service
        end

        def is_a?(klass)
          @service.is_a?(klass)
        end
        alias kind_of? is_a?
      end

      class SubjectService < BaseService
        def initialize
          @hook_subject = ClassHonestSubject.new(self)
        end

        private

        attr_reader :hook_subject

        def perform
          success("ok")
        end
      end

      def test_call_class_method_delegates_to_instance
        result = TestService.call(should_succeed: true, value: "hello")
        assert result.success?
        assert_equal "hello", result.value
      end

      def test_success_result
        result = TestService.call(should_succeed: true, value: { data: 123 })

        assert result.success?
        assert_not result.failure?
        assert_equal({ data: 123 }, result.value)
        assert_nil result.error
      end

      def test_failure_result
        result = TestService.call(should_succeed: false, error: "Something went wrong")

        assert_not result.success?
        assert result.failure?
        assert_nil result.value
        assert_equal "Something went wrong", result.error
      end

      def test_on_success_callback
        called = false
        received_value = nil

        TestService.call(should_succeed: true, value: "test") do |result|
          result.on_success do |value|
            called = true
            received_value = value
          end
        end

        assert called, "on_success should have been called"
        assert_equal "test", received_value
      end

      def test_on_failure_callback
        called = false
        received_error = nil

        TestService.call(should_succeed: false, error: "oops") do |result|
          result.on_failure do |error, _errors|
            called = true
            received_error = error
          end
        end

        assert called, "on_failure should have been called"
        assert_equal "oops", received_error
      end

      def test_on_success_not_called_on_failure
        called = false

        TestService.call(should_succeed: false, error: "fail") do |result|
          result.on_success { called = true }
        end

        assert_not called, "on_success should not be called on failure"
      end

      def test_on_failure_not_called_on_success
        called = false

        TestService.call(should_succeed: true, value: "ok") do |result|
          result.on_failure { called = true }
        end

        assert_not called, "on_failure should not be called on success"
      end

      def test_value_bang_returns_value_on_success
        result = TestService.call(should_succeed: true, value: "unwrapped")
        assert_equal "unwrapped", result.value!
      end

      def test_value_bang_raises_on_failure
        result = TestService.call(should_succeed: false, error: "error message")
        assert_raises(RuntimeError) { result.value! }
      end

      def test_chaining_callbacks
        success_called = false
        failure_called = false

        result = TestService.call(should_succeed: true, value: "chain")
        result
          .on_success { success_called = true }
          .on_failure { failure_called = true }

        assert success_called
        assert_not failure_called
      end

      def test_perform_not_implemented_raises
        assert_raises(NotImplementedError) { IncompleteService.call }
      end

      def test_result_errors_array
        result = BaseService::Result.new(
          success: false,
          error: "Main error",
          errors: ["Detail 1", "Detail 2"]
        )

        assert_equal ["Detail 1", "Detail 2"], result.errors
      end

      def test_hooks_run_for_service
        hooks = RecordingStudio.configuration.hooks
        hooks.clear!

        before_args = nil
        after_args = nil
        around_events = []

        hooks.before_service { |service_class, args| before_args = [service_class, args] }
        hooks.after_service { |service_class, result| after_args = [service_class, result] }
        hooks.around_service do |_service, block|
          around_events << :before
          result = block.call
          around_events << :after
          result
        end

        result = HookedService.call

        assert_equal HookedService, before_args.first
        assert_equal({ payload: "data" }, before_args.last)
        assert_equal HookedService, after_args.first
        assert_equal result, after_args.last
        assert_equal %i[before after], around_events
      ensure
        hooks.clear!
      end

      def test_default_hooks_see_the_service_and_the_caller_result
        hooks = RecordingStudio.configuration.hooks
        hooks.clear!

        around_service = nil
        around_result = nil
        after_result = nil
        caller_result = nil

        hooks.after_service { |_service_class, result| after_result = result }
        hooks.around_service do |service, block|
          around_service = service
          around_result = block.call
          around_result
        end

        returned = HookedService.call { |result| caller_result = result }

        assert_instance_of HookedService, around_service
        assert_same returned, around_result
        assert_same returned, after_result
        assert_same returned, caller_result
        assert_equal "ok", returned.value
      ensure
        hooks.clear!
      end

      def test_hook_result_redacts_after_service_and_keeps_the_caller_result
        hooks = RecordingStudio.configuration.hooks
        hooks.clear!

        after_result = nil
        caller_result = nil
        hooks.after_service { |_service_class, result| after_result = result }

        returned = RedactingService.call(secret: "plaintext") { |result| caller_result = result }

        assert_equal "redacted:plaintext", after_result.value
        assert_equal "plaintext", returned.value
        assert_same returned, caller_result
      ensure
        hooks.clear!
      end

      def test_pass_through_around_hook_sees_the_redacted_result
        hooks = RecordingStudio.configuration.hooks
        hooks.clear!

        shown = nil
        after_result = nil
        hooks.after_service { |_service_class, result| after_result = result }
        hooks.around_service do |_service, block|
          shown = block.call
          shown
        end

        returned = RedactingService.call(secret: "plaintext")

        assert_equal "redacted:plaintext", shown.value
        assert_equal "redacted:plaintext", after_result.value
        refute_same returned, shown
        assert_equal "plaintext", returned.value
      ensure
        hooks.clear!
      end

      def test_around_hook_return_value_replaces_the_caller_result
        hooks = RecordingStudio.configuration.hooks
        hooks.clear!

        shown = nil
        after_result = nil
        caller_result = nil
        replacement = BaseService::Result.new(success: true, value: "swapped")

        hooks.after_service { |_service_class, result| after_result = result }
        hooks.around_service do |_service, block|
          shown = block.call
          replacement
        end

        returned = RedactingService.call(secret: "plaintext") { |result| caller_result = result }

        assert_equal "redacted:plaintext", shown.value
        assert_same replacement, returned
        assert_same replacement, caller_result
        assert_equal "redacted:swapped", after_result.value
        refute_same replacement, after_result
      ensure
        hooks.clear!
      end

      def test_hook_subject_reaches_around_hooks_and_reports_the_service_class
        hooks = RecordingStudio.configuration.hooks
        hooks.clear!

        received = nil
        hooks.around_service do |subject, block|
          received = subject
          block.call
        end

        SubjectService.call

        assert_instance_of ClassHonestSubject, received
        assert received.is_a?(SubjectService)
        assert received.kind_of?(SubjectService) # rubocop:disable Style/ClassCheck
      ensure
        hooks.clear!
      end
    end
  end
end
