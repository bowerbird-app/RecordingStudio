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

      class DeclaredError < StandardError; end
      class DeclaredLimitError < DeclaredError; end
      class SiblingOnlyError < StandardError; end
      class SecondChildError < StandardError; end
      class AroundHookError < StandardError; end

      class UndeclaredService < BaseService
        def initialize(error: nil)
          @error = error
        end

        private

        def perform
          raise @error if @error

          success("ok")
        end
      end

      class HandlingService < UndeclaredService
        handles DeclaredError
      end

      class ReraisingService < BaseService
        handles DeclaredError
        reraises DeclaredLimitError

        def initialize(error:)
          @error = error
        end

        private

        def perform
          raise @error
        end
      end

      class ChildService < HandlingService
        handles SiblingOnlyError
        handles SecondChildError
        reraises DeclaredLimitError
      end

      class SiblingService < HandlingService
      end

      class OtherChildService < HandlingService
        handles AroundHookError
      end

      class LaterError < StandardError; end

      class HandlingService
        handles LaterError
      end

      class CustomFailureService < HandlingService
        private

        def handled_failure(exception)
          failure("translated", errors: [exception.class.name], value: exception.message)
        end
      end

      class RedactingHandledService < HandlingService
        private

        def hook_result(result)
          failure("redacted", value: result.error)
        end
      end

      class ValuedFailureService < BaseService
        private

        def perform
          failure("nope", errors: ["detail"], value: { kept: true })
        end
      end

      class AroundSensitiveService < BaseService
        handles AroundHookError

        private

        def perform
          success("ok")
        end
      end

      class HookResultBoomService < BaseService
        handles AroundHookError

        private

        def perform
          success("ok")
        end

        def hook_result(_result)
          raise AroundHookError, "from hook_result"
        end
      end

      class ReraiseOnlyService < BaseService
        reraises DeclaredError

        private

        def perform
          raise DeclaredError, "still raises"
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

      def test_handled_exception_becomes_a_failure
        seen = nil
        result = HandlingService.call(error: DeclaredError.new("full")) do |service_result|
          service_result.on_failure { |error, _errors| seen = error }
        end

        assert result.failure?
        assert_equal "full", result.error
        assert_nil result.value
        assert_empty result.errors
        assert_equal "full", seen
      end

      def test_unhandled_exception_raises
        with_service_hooks do |hooks|
          after_ran = false
          around_saw_raise = false
          hooks.after_service { after_ran = true }
          hooks.around_service do |_service, block|
            block.call
          rescue SiblingOnlyError
            around_saw_raise = true
            raise
          end

          error = assert_raises(SiblingOnlyError) do
            HandlingService.call(error: SiblingOnlyError.new("down"))
          end

          assert_equal "down", error.message
          assert around_saw_raise
          refute after_ran
        end
      end

      def test_reraises_beats_handles_for_a_subclass
        with_service_hooks do |hooks|
          after_ran = false
          around_saw_raise = false
          hooks.after_service { after_ran = true }
          hooks.around_service do |_service, block|
            block.call
          rescue DeclaredLimitError
            around_saw_raise = true
            raise
          end

          error = assert_raises(DeclaredLimitError) do
            ReraisingService.call(error: DeclaredLimitError.new("limit"))
          end

          assert_equal "limit", error.message
          assert around_saw_raise
          refute after_ran

          result = ReraisingService.call(error: DeclaredError.new("full"))
          assert result.failure?
          assert_equal "full", result.error
        end
      end

      def test_inherited_declarations_append_without_leaking
        assert_service_failure ChildService.call(error: DeclaredError.new("parent rule")), "parent rule"
        assert_service_failure ChildService.call(error: SiblingOnlyError.new("own")), "own"
        assert_service_failure ChildService.call(error: SecondChildError.new("second")), "second"
        assert_raises(DeclaredLimitError) { ChildService.call(error: DeclaredLimitError.new("limit")) }
        assert_raises(AroundHookError) { ChildService.call(error: AroundHookError.new("other child")) }

        assert_service_failure HandlingService.call(error: DeclaredError.new("parent")), "parent"
        assert_service_failure HandlingService.call(error: DeclaredLimitError.new("still handled")), "still handled"
        assert_raises(SiblingOnlyError) { HandlingService.call(error: SiblingOnlyError.new("child only")) }
        assert_raises(SecondChildError) { HandlingService.call(error: SecondChildError.new("child only")) }
        assert_raises(AroundHookError) { HandlingService.call(error: AroundHookError.new("other child")) }

        assert_service_failure SiblingService.call(error: DeclaredError.new("shared")), "shared"
        assert_service_failure(
          SiblingService.call(error: DeclaredLimitError.new("not reraised here")),
          "not reraised here"
        )
        assert_raises(SiblingOnlyError) { SiblingService.call(error: SiblingOnlyError.new("cousin")) }
        assert_raises(SecondChildError) { SiblingService.call(error: SecondChildError.new("cousin")) }
        assert_raises(AroundHookError) { SiblingService.call(error: AroundHookError.new("cousin")) }

        assert_service_failure OtherChildService.call(error: AroundHookError.new("mine")), "mine"
        assert_service_failure OtherChildService.call(error: DeclaredLimitError.new("still handled")), "still handled"
        assert_raises(SiblingOnlyError) { OtherChildService.call(error: SiblingOnlyError.new("not mine")) }

        assert_service_failure ChildService.call(error: LaterError.new("added later")), "added later"
        assert_service_failure SiblingService.call(error: LaterError.new("added later")), "added later"
        assert_service_failure HandlingService.call(error: LaterError.new("added later")), "added later"
        assert_raises(LaterError) { UndeclaredService.call(error: LaterError.new("above the parent")) }
      end

      def test_after_hooks_and_hook_result_run_on_a_handled_failure
        with_service_hooks do |hooks|
          shown = nil
          hooks.after_service { |_service_class, result| shown = result }

          returned = RedactingHandledService.call(error: DeclaredError.new("full"))

          assert returned.failure?
          assert_equal "full", returned.error
          assert_nil returned.value
          assert_equal "redacted", shown.error
          assert_equal "full", shown.value
        end
      end

      def test_around_hook_sees_the_failure_result
        with_service_hooks do |hooks|
          seen = nil
          rolled_back = false
          after_ran = false
          hooks.after_service { after_ran = true }
          hooks.around_service do |_service, block|
            seen = block.call
            seen
          rescue StandardError
            rolled_back = true
            raise
          end

          returned = HandlingService.call(error: DeclaredError.new("full"))

          assert_same returned, seen
          assert returned.failure?
          assert_equal "full", seen.error
          refute rolled_back
          assert after_ran
        end
      end

      def test_around_hook_exception_is_not_converted
        with_service_hooks do |hooks|
          after_ran = false
          hooks.after_service { after_ran = true }
          hooks.around_service do |_service, block|
            block.call
            raise AroundHookError, "from around"
          end

          error = assert_raises(AroundHookError) { AroundSensitiveService.call }

          assert_equal "from around", error.message
          refute after_ran
        end
      end

      def test_hook_result_exception_is_not_converted
        with_service_hooks do |hooks|
          after_ran = false
          hooks.after_service { after_ran = true }
          hooks.around_service { |_service, block| block.call }

          error = assert_raises(AroundHookError) { HookResultBoomService.call }

          assert_equal "from hook_result", error.message
          refute after_ran
        end

        with_service_hooks do
          assert_raises(AroundHookError) { HookResultBoomService.call }
        end
      end

      def test_handled_failure_override_is_used
        result = CustomFailureService.call(error: DeclaredError.new("full"))

        assert result.failure?
        assert_equal "translated", result.error
        assert_equal [DeclaredError.name], result.errors
        assert_equal "full", result.value
      end

      def test_failure_accepts_a_value
        result = ValuedFailureService.call

        assert result.failure?
        assert_equal "nope", result.error
        assert_equal ["detail"], result.errors
        assert_equal({ kept: true }, result.value)
      end

      def test_service_with_no_declarations_is_unchanged
        error = assert_raises(RuntimeError) do
          UndeclaredService.call(error: RuntimeError.new("boom"))
        end
        frame = error.backtrace.find { |line| line.include?("base_service.rb") }

        assert_equal "boom", error.message
        assert_match(/in `run_with_around_hooks'/, frame)
        refute_match(/perform_rescuing|run_handled_perform/, error.backtrace.join("\n"))

        with_service_hooks do |hooks|
          after_ran = false
          around_saw_raise = false
          hooks.after_service { after_ran = true }
          hooks.around_service do |_service, block|
            block.call
          rescue RuntimeError
            around_saw_raise = true
            raise
          end

          raised = assert_raises(RuntimeError) do
            UndeclaredService.call(error: RuntimeError.new("boom"))
          end
          around_frame = raised.backtrace.find { |line| line.include?("base_service.rb") }

          assert around_saw_raise
          refute after_ran
          assert_match(/block in run_with_around_hooks'/, around_frame)
        end

        assert_raises(DeclaredError) { ReraiseOnlyService.call }
        assert_equal "ok", UndeclaredService.call.value
      end

      private

      def with_service_hooks
        hooks = RecordingStudio.configuration.hooks
        hooks.clear!
        yield hooks
      ensure
        hooks&.clear!
      end

      def assert_service_failure(result, message)
        assert result.failure?, "expected failure, got #{result.error.inspect}"
        assert_equal message, result.error
      end
    end
  end
end
