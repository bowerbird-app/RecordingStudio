# frozen_string_literal: true

module RecordingStudio
  module Services
    class RootRecordingResolver < BaseService
      def initialize(actor:, device_fingerprint:, user_agent: nil)
        super()
        @actor = actor
        @device_fingerprint = device_fingerprint
        @user_agent = user_agent
      end

      private

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def perform
        return failure("Actor is required") unless @actor
        return failure("Device fingerprint is required") if @device_fingerprint.blank?

        session = RecordingStudio::DeviceSession.resolve(
          actor: @actor,
          device_fingerprint: @device_fingerprint,
          user_agent: @user_agent
        )

        return failure("No accessible root recordings found") unless session

        root_recording = RecordingStudio::Recording.unscoped.find_by(id: session.root_recording_id)
        return failure("Root recording no longer exists") unless root_recording

        accessible_ids = RecordingStudio::Services::AccessCheck
                         .root_recording_ids_for(actor: @actor)
                         .to_set

        unless accessible_ids.include?(root_recording.id)
          fallback_id = RecordingStudio::Services::AccessCheck
                        .root_recording_ids_for(actor: @actor)
                        .first
          return failure("No accessible root recordings") unless fallback_id

          session.transaction do
            session.lock!
            session.update!(root_recording_id: fallback_id)
          end

          root_recording = RecordingStudio::Recording.unscoped.find(fallback_id)
        end

        success(root_recording)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end
  end
end
