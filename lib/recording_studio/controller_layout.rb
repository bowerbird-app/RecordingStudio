# frozen_string_literal: true

require "active_support/concern"

module RecordingStudio
  # Class macro for engine and host controllers.
  #
  #   recording_studio_layout { RecordingStudioX.configuration.layout }
  #
  # The block is evaluated in the controller and returns that gem's layout
  # setting. Lookup is the setting when it is not nil, then
  # `RecordingStudio.configuration.layout`, then `RecordingStudio::DEFAULT_LAYOUT`.
  module ControllerLayout
    extend ActiveSupport::Concern

    class_methods do
      def recording_studio_layout(&block)
        @recording_studio_layout_block = block if block
        layout :recording_studio_resolved_layout
        helper RecordingStudio::LayoutHelper
      end

      def recording_studio_layout_block
        return @recording_studio_layout_block if instance_variable_defined?(:@recording_studio_layout_block)
        return unless superclass.respond_to?(:recording_studio_layout_block, true)

        superclass.send(:recording_studio_layout_block)
      end
      private :recording_studio_layout_block
    end

    def recording_studio_resolved_layout
      block = self.class.send(:recording_studio_layout_block)
      if block
        resolved = RecordingStudio::Layout.resolve(instance_exec(&block), controller: self)
        return resolved unless resolved.nil?
      end

      RecordingStudio.configuration.resolved_layout(controller: self)
    end
  end
end
