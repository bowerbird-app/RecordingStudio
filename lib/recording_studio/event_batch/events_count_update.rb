# frozen_string_literal: true

module RecordingStudio
  class EventBatch
    # Applies grouped events_count updates after the outermost transaction commits.
    class EventsCountUpdate
      def initialize(counts)
        @counts = counts
        @applied = false
      end

      def before_committed!; end

      def committed!(should_run_callbacks: true, **)
        return unless should_run_callbacks
        return if @applied

        @applied = true
        apply!
      end

      def rolledback!(**); end

      def trigger_transactional_callbacks?
        true
      end

      private

      def apply!
        @counts.each do |type, id, count|
          RecordingStudio.update_polymorphic_counter(type, id, :events_count, count)
        end
      end
    end
  end
end
