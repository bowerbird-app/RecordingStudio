# frozen_string_literal: true

module RecordingStudio
  class DeviceSession < ApplicationRecord
    self.table_name = "recording_studio_device_sessions"

    belongs_to :actor, polymorphic: true
    belongs_to :root_recording, class_name: "RecordingStudio::Recording"

    validates :device_fingerprint, presence: true
    validates :device_fingerprint, uniqueness: { scope: %i[actor_type actor_id] }
    validates :user_agent, length: { maximum: 255 }, allow_blank: true
    validate :root_recording_must_be_root

    scope :for_actor, ->(actor) {
      where(actor_type: actor.class.name, actor_id: actor.id)
    }

    scope :for_device, ->(fingerprint) {
      where(device_fingerprint: fingerprint)
    }

    def switch_to!(new_root_recording, minimum_role: :view)
      transaction do
        lock! # Lock the record

        accessible_ids = RecordingStudio::Services::AccessCheck
                          .root_recording_ids_for(actor: actor, minimum_role: minimum_role)
                          .to_set

        unless accessible_ids.include?(new_root_recording.id)
          raise RecordingStudio::AccessDenied,
                "Actor does not have access to the target root recording"
        end

        update!(
          root_recording: new_root_recording,
          last_active_at: Time.current
        )
      end
    end

    def self.resolve(actor:, device_fingerprint:, user_agent: nil)
      retry_count = 0
      begin
        session = find_or_create_by!(
          actor_type: actor.class.name,
          actor_id: actor.id,
          device_fingerprint: device_fingerprint
        ) do |s|
          default_root_id = RecordingStudio::Services::AccessCheck
                              .root_recording_ids_for(actor: actor)
                              .first

          return nil unless default_root_id

          s.root_recording_id = default_root_id
          s.user_agent = user_agent&.slice(0, 255)
          s.last_active_at = Time.current
        end

        session.touch(:last_active_at) unless session.previously_new_record?
        session
      rescue ActiveRecord::RecordInvalid => e
        # Retry once on race condition for uniqueness violation
        if retry_count.zero? && e.record.errors[:device_fingerprint].present?
          retry_count += 1
          retry
        end
        raise
      end
    end

    private

    def root_recording_must_be_root
      return if root_recording_id.blank?

      recording = RecordingStudio::Recording.unscoped
                    .where(parent_recording_id: nil)
                    .find_by(id: root_recording_id)

      return if recording

      errors.add(:root_recording, "must be a root recording (no parent)")
    end
  end
end
