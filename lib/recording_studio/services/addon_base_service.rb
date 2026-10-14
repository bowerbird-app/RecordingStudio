# frozen_string_literal: true

require_relative "base_service"

module RecordingStudio
  module Services
    # BaseService variant that fires hooks on an addon gem's own configuration.
    #
    # RecordingStudio::Services::BaseService always uses
    # `RecordingStudio.configuration.hooks`. Addon gems that keep a separate
    # hook registry on `SomeGem.configuration.hooks` should subclass this and
    # set `hooks_owner`.
    #
    # @example
    #   module RecordingStudioPublishable
    #     module Services
    #       class BaseService < ::RecordingStudio::Services::AddonBaseService
    #         self.hooks_owner = RecordingStudioPublishable
    #       end
    #     end
    #   end
    class AddonBaseService < BaseService
      class << self
        attr_accessor :hooks_owner
      end

      private

      def run_before_hooks
        return unless hooks_enabled?

        hooks_registry.run(:before_service, self.class, service_args)
      end

      def run_after_hooks(result)
        return unless hooks_enabled?

        hooks_registry.run(:after_service, self.class, result)
      end

      def run_with_around_hooks
        if hooks_enabled? && hooks_registry.registered?(:around_service)
          hooks_registry.run_around(:around_service, self) { perform }
        else
          perform
        end
      end

      def hooks_enabled?
        owner = self.class.hooks_owner
        !owner.nil? &&
          owner.respond_to?(:configuration) &&
          owner.configuration.respond_to?(:hooks)
      end

      def hooks_registry
        self.class.hooks_owner.configuration.hooks
      end
    end
  end
end
