# frozen_string_literal: true

module RecordingStudio
  module RecordingTrashableCounters
    extend ActiveSupport::Concern

    included do
      after_commit :increment_recordable_recordings_count, on: :create
      after_commit :decrement_recordable_recordings_count, on: :destroy
      after_commit :adjust_recordable_recordings_count, on: :update
    end

    private

    def increment_recordable_recordings_count
      return if trashed_at.present?

      update_recordable_counter(recordable_type, recordable_id, :recordings_count, 1)
    end

    def decrement_recordable_recordings_count
      return if trashed_at.present?

      update_recordable_counter(recordable_type, recordable_id, :recordings_count, -1)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def adjust_recordable_recordings_count
      if saved_change_to_trashed_at?
        if trashed_at_previously_was.nil? && trashed_at.present?
          update_recordable_counter(recordable_type, recordable_id, :recordings_count, -1)
        elsif trashed_at_previously_was.present? && trashed_at.nil?
          update_recordable_counter(recordable_type, recordable_id, :recordings_count, 1)
        end
      end

      return unless saved_change_to_recordable_id? || saved_change_to_recordable_type?
      return if trashed_at.present?

      previous_type = recordable_type_before_last_save
      previous_id = recordable_id_before_last_save

      update_recordable_counter(previous_type, previous_id, :recordings_count, -1) if previous_type && previous_id

      update_recordable_counter(recordable_type, recordable_id, :recordings_count, 1)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    def update_recordable_counter(recordable_type, recordable_id, column, delta)
      return unless recordable_type && recordable_id

      recordable_class = recordable_type.safe_constantize
      return unless recordable_class&.column_names&.include?(column.to_s)

      recordable_class.update_counters(recordable_id, column => delta)
    end
  end
end
