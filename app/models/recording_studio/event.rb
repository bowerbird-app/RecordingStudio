# frozen_string_literal: true

module RecordingStudio
  class Event < ApplicationRecord
    include RecordingStudio::Concerns::RecordableCounterCaches

    self.table_name = "recording_studio_events"

    ROOT_TIMELINE_LIMIT = 50
    TIMELINE_ORDER = { occurred_at: :desc, created_at: :desc, id: :desc }.freeze

    belongs_to :recording, class_name: "RecordingStudio::Recording", inverse_of: :events
    belongs_to :root_recording, class_name: "RecordingStudio::Recording"
    belongs_to :recordable, polymorphic: true
    belongs_to :previous_recordable, polymorphic: true, optional: true
    belongs_to :actor, polymorphic: true, optional: true
    belongs_to :impersonator, polymorphic: true, optional: true

    scope :for_recording, ->(recording) { where(recording: recording) }
    scope :for_root, lambda { |root_recording_or_id|
      root_id = if root_recording_or_id.respond_to?(:root_recording_id)
                  RecordingStudio.root_recording_id_for(root_recording_or_id)
                elsif root_recording_or_id.respond_to?(:id)
                  root_recording_or_id.id
                else
                  root_recording_or_id
                end
      next none if root_id.blank?

      where(root_recording_id: root_id)
    }
    scope :timeline, -> { order(TIMELINE_ORDER) }
    scope :older_than_cursor, lambda { |cursor|
      next all if cursor.blank?

      occurred_at, created_at, id = RecordingStudio::Event.cursor_point(cursor)
      where(
        "(recording_studio_events.occurred_at, recording_studio_events.created_at, recording_studio_events.id) " \
        "< (CAST(? AS timestamp), CAST(? AS timestamp), CAST(? AS uuid))",
        occurred_at, created_at, id
      )
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

    before_validation :assign_root_recording_id, on: :create
    before_update :raise_append_only_error
    before_destroy :raise_append_only_error
    after_commit :increment_recordable_events_count, on: :create
    after_commit :decrement_recordable_events_count, on: :destroy

    def readonly?
      persisted?
    end

    class << self
      def cursor_for(event)
        raise ArgumentError, "event is required" if event.blank?

        payload = {
          "occurred_at" => event.occurred_at.iso8601(6),
          "created_at" => event.created_at.iso8601(6),
          "id" => event.id
        }
        Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
      end

      def cursor_point(cursor)
        decoded = JSON.parse(Base64.urlsafe_decode64(cursor.to_s))
        occurred_at = Time.iso8601(decoded.fetch("occurred_at"))
        created_at = Time.iso8601(decoded.fetch("created_at"))
        id = decoded.fetch("id").to_s
        raise ArgumentError if occurred_at.nil? || created_at.nil? || id.blank?

        [occurred_at, created_at, id]
      rescue ArgumentError, JSON::ParserError, KeyError, TypeError
        raise ArgumentError, "cursor is invalid"
      end
    end

    private

    def assign_root_recording_id
      return if root_recording_id.present? || recording_id.blank?

      source = recording
      return if source.nil?

      self.root_recording_id = source.root_recording_id.presence || source.id
    end

    def raise_append_only_error
      raise ActiveRecord::ReadOnlyRecord,
            "Events are append-only; use RecordingStudio retention APIs that delete via SQL when purging history."
    end

    def increment_recordable_events_count
      update_recordable_counter(recordable_type, recordable_id, :events_count, 1)
    end

    def decrement_recordable_events_count
      update_recordable_counter(recordable_type, recordable_id, :events_count, -1)
    end
  end
end
