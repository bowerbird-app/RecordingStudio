# frozen_string_literal: true

module RecordingStudio
  class Event < ApplicationRecord
    include RecordingStudio::Concerns::RecordableCounterCaches

    self.table_name = "recording_studio_events"

    belongs_to :recording, class_name: "RecordingStudio::Recording", inverse_of: :events
    belongs_to :recordable, polymorphic: true
    belongs_to :previous_recordable, polymorphic: true, optional: true
    belongs_to :actor, polymorphic: true, optional: true
    belongs_to :impersonator, polymorphic: true, optional: true

    scope :for_recording, ->(recording) { where(recording: recording) }
    scope :for_root, lambda { |root_recording_or_id|
      root_id = root_recording_or_id.respond_to?(:id) ? root_recording_or_id.id : root_recording_or_id
      next none if root_id.blank?

      joins(:recording).where(recording_studio_recordings: { root_recording_id: root_id })
    }
    scope :by_actor, lambda { |actor|
      return none unless actor

      where(actor_type: actor.class.name, actor_id: actor.id)
    }
    scope :by_impersonator, lambda { |impersonator|
      return none unless impersonator

      where(impersonator_type: impersonator.class.name, impersonator_id: impersonator.id)
    }
    scope :with_action, ->(action) { where(action: action) }
    scope :between, lambda { |from_time = nil, to_time = nil|
      scope = all
      scope = scope.where(occurred_at: from_time..) if from_time.present?
      scope = scope.where(occurred_at: ..to_time) if to_time.present?
      scope
    }
    scope :recent, -> { order(occurred_at: :desc, created_at: :desc) }

    after_commit :increment_recordable_events_count, on: :create
    after_commit :decrement_recordable_events_count, on: :destroy

    private

    def increment_recordable_events_count
      update_recordable_counter(recordable_type, recordable_id, :events_count, 1)
    end

    def decrement_recordable_events_count
      update_recordable_counter(recordable_type, recordable_id, :events_count, -1)
    end
  end
end
