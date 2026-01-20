# frozen_string_literal: true

module ControlRoom
  class Event < ApplicationRecord
    self.table_name = "control_room_events"

    belongs_to :recording, class_name: "ControlRoom::Recording", inverse_of: :events
    belongs_to :recordable, polymorphic: true
    belongs_to :previous_recordable, polymorphic: true, optional: true
    belongs_to :actor, polymorphic: true, optional: true

    scope :for_recording, ->(recording) { where(recording: recording) }
    scope :by_actor, lambda { |actor|
      return none unless actor

      where(actor_type: actor.class.name, actor_id: actor.id)
    }
    scope :with_action, ->(action) { where(action: action) }
    scope :recent, -> { order(occurred_at: :desc, created_at: :desc) }
  end
end
