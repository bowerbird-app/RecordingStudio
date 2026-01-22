# frozen_string_literal: true

module RecordingStudio
  class Recording < ApplicationRecord
    self.table_name = "recording_studio_recordings"

    belongs_to :container, polymorphic: true
    belongs_to :parent_recording, class_name: "RecordingStudio::Recording", optional: true, inverse_of: :child_recordings
    has_many :child_recordings, class_name: "RecordingStudio::Recording", foreign_key: :parent_recording_id,
                  inverse_of: :parent_recording
    has_many :events, class_name: "RecordingStudio::Event", inverse_of: :recording, dependent: :destroy

    after_commit :increment_recordable_recordings_count, on: :create
    after_commit :decrement_recordable_recordings_count, on: :destroy
    after_commit :adjust_recordable_recordings_count, on: :update

    default_scope { where(discarded_at: nil) }
    scope :recent, -> { order(updated_at: :desc) }
    scope :for_container, ->(container) { where(container_type: container.class.name, container_id: container.id) }
    scope :kept, -> { unscope(where: :discarded_at).where(discarded_at: nil) }
    scope :discarded, -> { unscope(where: :discarded_at).where.not(discarded_at: nil) }
    scope :archived, -> { discarded }
    scope :with_archived, -> { unscope(where: :discarded_at) }
    scope :of_type, ->(klass) { where(recordable_type: klass.to_s) }

    def log_event!(action:, actor: nil, metadata: {}, occurred_at: Time.current, idempotency_key: nil)
      RecordingStudio.record!(
        action: action,
        recordable: recordable,
        recording: self,
        container: container,
        actor: actor,
        metadata: metadata,
        occurred_at: occurred_at,
        idempotency_key: idempotency_key
      )
    end

    private

    def increment_recordable_recordings_count
      return if discarded_at.present?

      update_recordable_counter(recordable_type, recordable_id, :recordings_count, 1)
    end

    def decrement_recordable_recordings_count
      return if discarded_at.present?

      update_recordable_counter(recordable_type, recordable_id, :recordings_count, -1)
    end

    def adjust_recordable_recordings_count
      if saved_change_to_discarded_at?
        if discarded_at_previously_was.nil? && discarded_at.present?
          update_recordable_counter(recordable_type, recordable_id, :recordings_count, -1)
        elsif discarded_at_previously_was.present? && discarded_at.nil?
          update_recordable_counter(recordable_type, recordable_id, :recordings_count, 1)
        end
      end

      return unless (saved_change_to_recordable_id? || saved_change_to_recordable_type?)
      return if discarded_at.present?

      previous_type = recordable_type_before_last_save
      previous_id = recordable_id_before_last_save

      if previous_type && previous_id
        update_recordable_counter(previous_type, previous_id, :recordings_count, -1)
      end

      update_recordable_counter(recordable_type, recordable_id, :recordings_count, 1)
    end

    def update_recordable_counter(recordable_type, recordable_id, column, delta)
      return unless recordable_type && recordable_id

      recordable_class = recordable_type.safe_constantize
      return unless recordable_class&.column_names&.include?(column.to_s)

      quoted_column = recordable_class.connection.quote_column_name(column)
      recordable_class.where(id: recordable_id)
        .update_all("#{quoted_column} = COALESCE(#{quoted_column}, 0) + #{delta}")
    end
  end
end