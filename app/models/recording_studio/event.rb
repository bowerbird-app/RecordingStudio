# frozen_string_literal: true

module RecordingStudio
  class Event < ApplicationRecord
    self.table_name = "recording_studio_events"

    belongs_to :recording, class_name: "RecordingStudio::Recording", inverse_of: :events
    belongs_to :recordable, polymorphic: true
    belongs_to :previous_recordable, polymorphic: true, optional: true
    belongs_to :actor, polymorphic: true, optional: true
    belongs_to :impersonator, polymorphic: true, optional: true

    scope :for_recording, ->(recording) { where(recording: recording) }
    scope :by_actor, lambda { |actor|
      return none unless actor

      where(actor_type: actor.class.name, actor_id: actor.id)
    }
    scope :with_action, ->(action) { where(action: action) }
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
