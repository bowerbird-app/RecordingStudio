# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    module Commentable
      def self.to(comment_class:)
        klass_name = comment_class.is_a?(Class) ? comment_class.name : comment_class.to_s
        RecordingStudio::Capabilities.include_for(:commentable, comment_class: klass_name) do
          RecordingStudio.register_recordable_type(klass_name)
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
end

RecordingStudio.register_capability(
  :commentable,
  recording_methods: RecordingStudio::Capabilities::Commentable::RecordingMethods,
  source: RecordingStudio::Capabilities::Commentable,
  child_recordables: "RecordingStudioComment"
)
