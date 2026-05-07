# frozen_string_literal: true

module RecordingStudio
  module CounterCaches
    module_function

    # rubocop:disable Naming/PredicateMethod
    def change_polymorphic_counter(recordable_or_type, recordable_id, column, delta)
      return false if recordable_id.blank? || column.blank?

      change = Integer(delta, exception: false)
      return false if change.nil? || change.zero?

      recordable_class = RecordingStudio::Identity.resolve_type(recordable_or_type)
      return false unless recordable_class && RecordingStudio::Identity.column?(recordable_class, column)

      recordable_class.update_counters(recordable_id, column.to_sym => change)
      true
    end
    # rubocop:enable Naming/PredicateMethod
  end
end
