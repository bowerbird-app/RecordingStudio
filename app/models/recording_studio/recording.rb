# frozen_string_literal: true

module RecordingStudio
  # rubocop:disable Metrics/ClassLength
  class Recording < ApplicationRecord
    include RecordingStudio::Concerns::RecordableIdentity
    include RecordingStudio::Concerns::RecordingHierarchy
    include RecordingStudio::Concerns::RecordableCounterCaches
    include RecordingStudio::Concerns::RecordableDuplication
    include RecordingStudio::Concerns::RecordingPresentation
    include RecordingStudio::Concerns::RecordingsQuery

    self.table_name = "recording_studio_recordings"

    belongs_to :root_recording, class_name: "RecordingStudio::Recording", optional: true
    belongs_to :parent_recording, class_name: "RecordingStudio::Recording", optional: true,
                                  inverse_of: :child_recordings
    has_many :child_recordings, class_name: "RecordingStudio::Recording", foreign_key: :parent_recording_id,
                                inverse_of: :parent_recording, dependent: :nullify
    has_many :events, -> { recent }, class_name: "RecordingStudio::Event", inverse_of: :recording, dependent: :destroy

    validate :parent_recording_root_consistency
    validate :parent_recording_must_not_create_cycle

    before_create :assign_root_recording_id
    after_create :set_self_root_recording_id, if: -> { parent_recording_id.nil? && root_recording_id.nil? }
    after_commit :increment_recordable_recordings_count, on: :create
    after_commit :decrement_recordable_recordings_count, on: :destroy
    after_commit :refresh_recordable_recordings_count, on: :update

    default_scope { order(updated_at: :desc) }
    scope :recent, -> { order(updated_at: :desc) }
    scope :for_root, ->(root_id) { where(root_recording_id: root_id) }
    scope :of_type, ->(klass) { where(recordable_type: klass.to_s) }

    def events(actions: nil, actor: nil, actor_type: nil, actor_id: nil, from: nil, to: nil, limit: nil, offset: nil)
      scope = association(:events).scope
      scope = scope.with_action(actions) if actions.present?
      scope = scope.by_actor(actor) if actor.present?
      scope = scope.where(actor_type: actor_type) if actor_type.present?
      scope = scope.where(actor_id: actor_id) if actor_id.present?
      scope = scope.where(occurred_at: from..) if from.present?
      scope = scope.where(occurred_at: ..to) if to.present?
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def record(recordable_or_class, actor: nil, impersonator: nil, metadata: {}, parent_recording: nil)
      recordable = build_recordable_instance(recordable_or_class)
      yield(recordable) if block_given?
      recordable.save!

      root = root_recording_or_self
      resolved_parent = parent_recording || root

      RecordingStudio.record!(
        action: "created",
        recordable: recordable,
        root_recording: root,
        parent_recording: resolved_parent,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata
      ).recording
    end

    def revise(recording, actor: nil, impersonator: nil, metadata: {})
      assert_recording_belongs_to_root!(recording)

      recordable = duplicate_recordable(recording.recordable)
      yield(recordable) if block_given?
      recordable.save!

      RecordingStudio.record!(
        action: "updated",
        recordable: recordable,
        recording: recording,
        root_recording: root_recording_or_self,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata
      ).recording
    end

    def log_event(recording = self, action:, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current,
                  idempotency_key: nil)
      assert_recording_belongs_to_root!(recording)

      recording.log_event!(
        action: action,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata,
        occurred_at: occurred_at,
        idempotency_key: idempotency_key
      )
    end

    def revert(recording, to_recordable:, actor: nil, impersonator: nil, metadata: {})
      assert_recording_belongs_to_root!(recording)

      RecordingStudio.record!(
        action: "reverted",
        recordable: to_recordable,
        recording: recording,
        root_recording: root_recording_or_self,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata
      ).recording
    end

    def recordings_of(recordable_class)
      recordings_query.of_type(recordable_class)
    end

    def log_event!(action:, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current,
                   idempotency_key: nil)
      RecordingStudio.record!(
        action: action,
        recordable: recordable,
        recording: self,
        root_recording: root_recording_or_self,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata,
        occurred_at: occurred_at,
        idempotency_key: idempotency_key
      )
    end

    private

    def build_recordable_instance(recordable_or_class)
      recordable_or_class.is_a?(Class) ? recordable_or_class.new : recordable_or_class
    end

    def increment_recordable_recordings_count
      update_recordable_counter(recordable_type, recordable_id, :recordings_count, 1)
    end

    def decrement_recordable_recordings_count
      update_recordable_counter(recordable_type, recordable_id, :recordings_count, -1)
    end

    def refresh_recordable_recordings_count
      return unless previous_changes.key?("recordable_type") || previous_changes.key?("recordable_id")

      previous_type = attribute_before_last_save("recordable_type")
      previous_id = attribute_before_last_save("recordable_id")

      update_recordable_counter(previous_type, previous_id, :recordings_count, -1)
      update_recordable_counter(recordable_type, recordable_id, :recordings_count, 1)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
