# frozen_string_literal: true

module Capabilities
  module Commentable
    def self.with(comment_class:)
      klass_name = comment_class.is_a?(Class) ? comment_class.name : comment_class.to_s
      Module.new do
        extend ActiveSupport::Concern

        included do |base|
          RecordingStudio.enable_capability(:commentable, on: base.name)
          RecordingStudio.set_capability_options(:commentable, on: base.name, comment_class: klass_name)
          RecordingStudio.register_recordable_type(klass_name)
        end
      end
    end

    module RecordingMethods
      include RecordingStudio::Capability

      def comment!(body:, actor:, impersonator: nil, metadata: {})
        assert_capability!(:commentable)
        opts = RecordingStudio.capability_options(:commentable, for_type: recordable_type) || {}
        klass = opts.fetch(:comment_class).safe_constantize
        raise ArgumentError, "Unknown comment class" unless klass

        comment = klass.new(body: body)
        record(comment, actor: actor, impersonator: impersonator, metadata: metadata, parent_recording: self)
      end

      def comments
        assert_capability!(:commentable)
        opts = RecordingStudio.capability_options(:commentable, for_type: recordable_type) || {}
        klass = opts.fetch(:comment_class).safe_constantize
        child_recordings.of_type(klass.name)
      end
    end
  end
end

RecordingStudio.register_capability(:commentable, Capabilities::Commentable::RecordingMethods)
RecordingStudio.apply_capabilities! if defined?(RecordingStudio::Recording)
