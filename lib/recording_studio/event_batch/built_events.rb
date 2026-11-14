# frozen_string_literal: true

require "securerandom"

module RecordingStudio
  class EventBatch
    # Builds in-memory events and validates them before the INSERT.
    class BuiltEvents
      REQUIRED_ATTRIBUTES = %i[
        action recording_id recordable_type recordable_id root_recording_id occurred_at created_at
      ].freeze

      def self.build(contexts)
        new(contexts).build
      end

      def initialize(contexts)
        @contexts = contexts
      end

      def build
        created_at = Time.current
        @contexts.map { |context| build_event(context, created_at) }.each { |event| validate_event!(event) }
      end

      private

      def build_event(context, created_at)
        event = RecordingStudio::Event.new(event_identity(context))
        assign_event_links(event, context)
        assign_event_times(event, context, created_at)
        event
      end

      def event_identity(context)
        recordable = context.fetch(:recordable)
        type_name = recordable.class.polymorphic_name
        {
          id: SecureRandom.uuid,
          action: context.fetch(:action),
          recordable_type: type_name,
          recordable_id: recordable.id,
          previous_recordable_type: type_name,
          previous_recordable_id: recordable.id
        }
      end

      def assign_event_links(event, context)
        recordable = context.fetch(:recordable)
        event.recording = context.fetch(:recording)
        event.root_recording = context.fetch(:root_recording)
        event.recordable = recordable
        event.previous_recordable = recordable
        event.actor = context[:actor]
        event.impersonator = context[:impersonator]
        copy_previous_recordable!(event, recordable)
      end

      def copy_previous_recordable!(event, recordable)
        event.previous_recordable_type = recordable.class.polymorphic_name
        event.previous_recordable_id = recordable.id
      end

      def assign_event_times(event, context, created_at)
        event.metadata = context.fetch(:metadata)
        event.occurred_at = context.fetch(:occurred_at)
        event.created_at = created_at
      end

      def validate_event!(event)
        event.validate!
        missing = REQUIRED_ATTRIBUTES.select { |name| event.read_attribute(name).nil? }
        return if missing.empty?

        missing.each { |name| event.errors.add(name, "can't be blank") }
        raise ActiveRecord::RecordInvalid, event
      end
    end
  end
end
