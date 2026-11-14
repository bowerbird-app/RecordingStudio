# frozen_string_literal: true

module RecordingStudio
  module RecordingFilters
    class << self
      def kept?(recording, &query)
        registered = snapshot
        return true if registered.empty?
        return predicate_kept?(registered, recording) if predicates_only?(registered)
        return true if recording.new_record?

        query.call
      end

      private

      def predicates_only?(registered)
        registered.all?(&:predicate)
      end

      def predicate_kept?(registered, recording)
        registered.all? { |filter| predicate_value(filter, recording) }
      end

      def predicate_value(filter, recording)
        result = filter.predicate.call(recording)
        return result if [true, false].include?(result)

        raise ArgumentError, "recording filter #{filter.name.inspect} predicate must return true or false"
      end
    end
  end
end
