# frozen_string_literal: true

module RecordingStudio
  class Recording < ApplicationRecord
    self.table_name = "recording_studio_recordings"

    belongs_to :container, polymorphic: true
    belongs_to :parent_recording, class_name: "RecordingStudio::Recording", optional: true,
                                  inverse_of: :child_recordings
    has_many :child_recordings, class_name: "RecordingStudio::Recording", foreign_key: :parent_recording_id,
                                inverse_of: :parent_recording
    has_many :events, -> { recent }, class_name: "RecordingStudio::Event", inverse_of: :recording, dependent: :destroy

    validate :parent_recording_container_consistency

    after_commit :increment_recordable_recordings_count, on: :create
    after_commit :decrement_recordable_recordings_count, on: :destroy
    after_commit :adjust_recordable_recordings_count, on: :update

    default_scope { where(trashed_at: nil).order(updated_at: :desc) }
    scope :recent, -> { order(updated_at: :desc) }
    scope :for_container, ->(container) { where(container_type: container.class.name, container_id: container.id) }
    scope :trashed, -> { unscope(where: :trashed_at).where.not(trashed_at: nil) }
    scope :including_trashed, -> { unscope(where: :trashed_at) }
    scope :include_trashed, -> { unscope(where: :trashed_at) }
    scope :of_type, ->(klass) { where(recordable_type: klass.to_s) }

    def events(actions: nil, actor: nil, actor_type: nil, actor_id: nil, from: nil, to: nil, limit: nil, offset: nil)
      scope = association(:events).scope
      scope = scope.with_action(actions) if actions.present?
      scope = scope.by_actor(actor) if actor.present?
      scope = scope.where(actor_type: actor_type) if actor_type.present?
      scope = scope.where(actor_id: actor_id) if actor_id.present?
      scope = scope.where("occurred_at >= ?", from) if from.present?
      scope = scope.where("occurred_at <= ?", to) if to.present?
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def log_event!(action:, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current,
                   idempotency_key: nil)
      RecordingStudio.record!(
        action: action,
        recordable: recordable,
        recording: self,
        container: container,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata,
        occurred_at: occurred_at,
        idempotency_key: idempotency_key
      )
    end

    def trash(actor: nil, metadata: {}, include_children: false)
      container.trash(self, actor: actor, metadata: metadata, include_children: include_children)
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

    def update_recordable_counter(recordable_type, recordable_id, column, delta)
      return unless recordable_type && recordable_id

      recordable_class = recordable_type.safe_constantize
      return unless recordable_class&.column_names&.include?(column.to_s)

      quoted_column = recordable_class.connection.quote_column_name(column)
      recordable_class.where(id: recordable_id)
                      .update_all("#{quoted_column} = COALESCE(#{quoted_column}, 0) + #{delta}")
    end

    def parent_recording_container_consistency
      return unless parent_recording

      return if parent_recording.container_type == container_type && parent_recording.container_id == container_id

      errors.add(:parent_recording_id, "must belong to the same container")
    end
  end
end
