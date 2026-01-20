# frozen_string_literal: true

module ControlRoom
  class Recording < ApplicationRecord
    self.table_name = "control_room_recordings"

    belongs_to :container, polymorphic: true
    has_many :events, class_name: "ControlRoom::Event", inverse_of: :recording, dependent: :destroy

    scope :recent, -> { order(updated_at: :desc) }
    scope :for_container, ->(container) { where(container_type: container.class.name, container_id: container.id) }
    scope :kept, -> { where(discarded_at: nil) }
    scope :discarded, -> { where.not(discarded_at: nil) }
    scope :of_type, ->(klass) { where(recordable_type: klass.to_s) }

    def log_event!(action:, actor: nil, metadata: {}, occurred_at: Time.current, idempotency_key: nil)
      ControlRoom.record!(
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
  end
end
