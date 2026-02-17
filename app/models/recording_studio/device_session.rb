# frozen_string_literal: true

module RecordingStudio
  class DeviceSession < ApplicationRecord
    self.table_name = "recording_studio_device_sessions"

    belongs_to :actor, polymorphic: true
    belongs_to :root_recording, class_name: "RecordingStudio::Recording"

    validates :device_fingerprint, presence: true
    validates :device_fingerprint, uniqueness: { scope: %i[actor_type actor_id] }
    validate :root_recording_must_be_root

    scope :for_actor, ->(actor) {
      where(actor_type: actor.class.name, actor_id: actor.id)
    }

    scope :for_device, ->(fingerprint) {
      where(device_fingerprint: fingerprint)
    }

    def switch_to!(new_root_recording, minimum_role: :view)
      unless RecordingStudio::Services::AccessCheck
               .root_recording_ids_for(actor: actor, minimum_role: minimum_role)
               .include?(new_root_recording.id)
        raise RecordingStudio::AccessDenied,
              "Actor does not have access to the target root recording"
      end

      update!(
        root_recording: new_root_recording,
        last_active_at: Time.current
      )
    end

    def self.resolve(actor:, device_fingerprint:, user_agent: nil)
      session = find_or_initialize_by(
        actor_type: actor.class.name,
        actor_id: actor.id,
        device_fingerprint: device_fingerprint
      )

      if session.new_record?
        default_root_id = RecordingStudio::Services::AccessCheck
                            .root_recording_ids_for(actor: actor)
                            .first

        return nil unless default_root_id

        session.root_recording_id = default_root_id
        session.user_agent = user_agent
        session.last_active_at = Time.current
        session.save!
      else
        session.touch(:last_active_at)
      end

      session
    end

    private

    def root_recording_must_be_root
      return if root_recording_id.blank?

      recording = RecordingStudio::Recording.unscoped.find_by(id: root_recording_id)
      return if recording&.parent_recording_id.nil?

      errors.add(:root_recording, "must be a root recording (no parent)")
    end
  end
end
