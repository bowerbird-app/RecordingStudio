# frozen_string_literal: true

require "recording_studio/event_batch/contexts"
require "recording_studio/event_batch/built_events"
require "recording_studio/event_batch/events_count_update"

module RecordingStudio
  class EventBatch
    # Authorizes, inserts, and publishes a prepared batch.
    class Commit
      def self.call(prepared)
        new(prepared).call
      end

      def initialize(prepared)
        @prepared = prepared
      end

      def call
        contexts = Contexts.bind(@prepared)
        events = BuiltEvents.build(contexts)
        authorize!(contexts)
        before_hooks!(contexts)
        insert!(events)
        publish!(events)
        schedule_counters!(events)
        events
      end

      private

      def authorize!(contexts)
        contexts.each { |context| RecordingStudio::Authorization.authorize_write!(**write_context(context)) }
      end

      def before_hooks!(contexts)
        contexts.each { |context| RecordingStudio::Hooks.run(:before_record, **write_context(context)) }
      end

      def write_context(context)
        {
          action: context.fetch(:action),
          recordable: context.fetch(:recordable),
          recording: context.fetch(:recording),
          root_recording: context.fetch(:root_recording),
          parent_recording: nil,
          actor: context[:actor],
          impersonator: context[:impersonator],
          metadata: context.fetch(:metadata)
        }
      end

      def insert!(events)
        RecordingStudio::Event.insert_all!(events.map(&:attributes))
        events.each(&:changes_applied)
      end

      def publish!(events)
        events.each do |event|
          RecordingStudio.send(:instrument_event, event)
          RecordingStudio::Hooks.run(:after_record, event)
        end
      end

      def schedule_counters!(events)
        counts = counter_groups(events)
        return if counts.empty?

        record = EventsCountUpdate.new(counts)
        RecordingStudio::Recording.connection.add_transaction_record(record)
      end

      def counter_groups(events)
        events.group_by { |event| [event.recordable_type, event.recordable_id] }.map do |(type, id), grouped|
          [type, id, grouped.size]
        end
      end
    end
  end
end
