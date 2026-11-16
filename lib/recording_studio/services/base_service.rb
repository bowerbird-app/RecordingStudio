# frozen_string_literal: true

module RecordingStudio
  module Services
    # Class-level handled and reraised exception lists for BaseService.
    # Each class stores only the classes it declares. The list in force walks ancestors
    # and appends those classes, so a later declaration on the parent stays visible.
    module ExceptionDeclarations
      # Turn these exception classes from `perform` into a failure.
      #
      # @param exception_classes [Array<Class>]
      # @return [Array<Class>]
      def handles(*exception_classes)
        @handled_exception_classes = append_exception_classes(:@handled_exception_classes, exception_classes)
      end

      # Keep these exception classes propagating when `perform` raises them.
      # A match here wins over `handles`, including a subclass of a handled class.
      #
      # @param exception_classes [Array<Class>]
      # @return [Array<Class>]
      def reraises(*exception_classes)
        @reraised_exception_classes = append_exception_classes(:@reraised_exception_classes, exception_classes)
      end

      EMPTY_EXCEPTION_CLASSES = [].freeze
      private_constant :EMPTY_EXCEPTION_CLASSES

      private

      def handled_exception_classes
        combine_exception_classes(:@handled_exception_classes, :handled_exception_classes)
      end

      def reraised_exception_classes
        combine_exception_classes(:@reraised_exception_classes, :reraised_exception_classes)
      end

      def append_exception_classes(ivar, exception_classes)
        own_exception_classes(ivar).dup.concat(exception_classes).freeze
      end

      def own_exception_classes(ivar)
        return instance_variable_get(ivar) if instance_variable_defined?(ivar)

        EMPTY_EXCEPTION_CLASSES
      end

      def combine_exception_classes(ivar, reader)
        own = own_exception_classes(ivar)
        parent = superclass
        return own unless parent.respond_to?(reader, true)

        inherited = parent.send(reader)
        return own if inherited.empty?
        return inherited if own.empty?

        inherited + own
      end
    end
    private_constant :ExceptionDeclarations

    # Base class for service objects following the Command pattern.
    #
    # Services encapsulate business logic and provide a consistent interface
    # with `.call` class method and a Result object for success/failure handling.
    #
    # Services support hooks for instrumentation and customization:
    # - before_service: Called before service execution
    # - after_service: Called after service execution (with result)
    # - around_service: Wraps service execution
    #
    # Override `hook_result` to show hooks a redacted result, and `hook_subject`
    # to show `around_service` something other than the service. `call` still
    # returns the real result.
    #
    # `handles` turns exceptions raised by `perform` into failures. `reraises`
    # keeps matching exceptions propagating, and it wins when both lists match.
    # Core declares neither.
    #
    # @example Basic usage
    #   result = MyService.call(param1: "value")
    #   if result.success?
    #     puts result.value
    #   else
    #     puts result.error
    #   end
    #
    # @example With block for error handling
    #   MyService.call(param1: "value") do |result|
    #     result.on_success { |value| puts "Success: #{value}" }
    #     result.on_failure { |error| puts "Error: #{error}" }
    #   end
    #
    class BaseService
      # Result object returned by all services
      class Result
        attr_reader :value, :error, :errors

        def initialize(success:, value: nil, error: nil, errors: [])
          @success = success
          @value = value
          @error = error
          @errors = errors
        end

        def success?
          @success
        end

        def failure?
          !@success
        end

        def on_success
          yield(value) if success? && block_given?
          self
        end

        def on_failure
          yield(error, errors) if failure? && block_given?
          self
        end

        # Unwrap the value or raise an error
        def value!
          raise error if failure?

          value
        end
      end

      class << self
        # Main entry point for calling the service
        #
        # @param args [Hash] Arguments passed to the service
        # @yield [Result] Optional block for handling the result
        # @return [Result] The result of the service call
        def call(*, **, &)
          new(*, **).call(&)
        end
      end
      extend ExceptionDeclarations

      # Execute the service logic with hooks
      #
      # @yield [Result] Optional block for handling the result
      # @return [Result] The result of the service call
      def call
        # Run before_service hooks
        run_before_hooks

        # Run around_service hooks (or just perform if none registered)
        result = run_with_around_hooks

        # Run after_service hooks
        run_after_hooks(result)

        yield(result) if block_given?
        result
      end

      private

      # Override this method in subclasses to implement service logic
      #
      # @return [Result] The result of the operation
      def perform
        raise NotImplementedError, "#{self.class}#perform must be implemented"
      end

      # Helper to return a success result
      #
      # @param value [Object] The successful value
      # @return [Result] A success result
      def success(value = nil)
        Result.new(success: true, value: value)
      end

      # Helper to return a failure result
      #
      # @param error [String, StandardError] The error message or exception
      # @param errors [Array] Additional error details
      # @param value [Object] Value kept with the failure
      # @return [Result] A failure result
      def failure(error, errors: [], value: nil)
        error_message = error.is_a?(Exception) ? error.message : error
        Result.new(success: false, error: error_message, errors: errors, value: value)
      end

      # Failure returned for an exception declared with `handles`.
      # Override to choose `errors` or `value`. The default stores the exception message.
      #
      # @param exception [Exception]
      # @return [Result]
      def handled_failure(exception)
        failure(exception)
      end

      # Run before_service hooks
      def run_before_hooks
        return unless hooks_enabled?

        RecordingStudio::Hooks.run(:before_service, self.class, service_args)
      end

      # Run after_service hooks
      def run_after_hooks(result)
        return unless hooks_enabled?

        RecordingStudio::Hooks.run(:after_service, self.class, hook_result(result))
      end

      # Undeclared services call `perform` on this stack. A wrapper would change their backtrace.
      def run_with_around_hooks
        handling = self.class.send(:handled_exception_classes)
        return run_handled_perform(handling) if handling.any?

        return perform unless around_service_registered?

        real = nil
        hook_view = nil
        returned = RecordingStudio::Hooks.run_around(:around_service, hook_subject) do
          real = perform
          hook_view = hook_result(real)
        end

        returned.equal?(hook_view) ? real : returned
      end

      def run_handled_perform(handling)
        return perform_rescuing(handling) unless around_service_registered?

        real = nil
        hook_view = nil
        returned = RecordingStudio::Hooks.run_around(:around_service, hook_subject) do
          real = perform_rescuing(handling)
          hook_view = hook_result(real)
        end

        returned.equal?(hook_view) ? real : returned
      end

      def perform_rescuing(handling)
        perform
      rescue *handling => e
        raise if reraised_exception?(e)

        handled_failure(e)
      end

      def reraised_exception?(exception)
        self.class.send(:reraised_exception_classes).any? do |exception_class|
          exception.is_a?(exception_class)
        end
      end

      def around_service_registered?
        hooks_enabled? && RecordingStudio.configuration.hooks.registered?(:around_service)
      end

      # Check if hooks are enabled (RecordingStudio is loaded and configured)
      #
      # @return [Boolean]
      def hooks_enabled?
        defined?(RecordingStudio) &&
          RecordingStudio.respond_to?(:configuration) &&
          RecordingStudio.configuration.respond_to?(:hooks)
      end

      # Get service arguments for hook callbacks
      # Override in subclasses to provide meaningful args
      #
      # @return [Hash] Arguments passed to the service
      def service_args
        {}
      end

      # Object hooks should see for a result. The default returns `result`.
      #
      # `after_service` receives this value for the caller-facing result.
      # The block passed to `around_service` returns this value for the
      # `perform` result. When the hook returns that same object, `call`
      # returns the real result. Any other object replaces it.
      #
      # @param result [Object] Result a hook is about to see
      # @return [Object]
      def hook_result(result)
        result
      end

      # Object passed to `around_service` instead of the service.
      # The default is the service.
      #
      # @return [Object]
      def hook_subject
        self
      end
    end
  end
end
