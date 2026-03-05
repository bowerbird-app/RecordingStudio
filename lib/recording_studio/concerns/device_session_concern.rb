# frozen_string_literal: true

module RecordingStudio
  module Concerns
    module DeviceSessionConcern
      extend ActiveSupport::Concern

      included do
        helper_method :current_root_recording, :current_device_session if respond_to?(:helper_method)
      end

      private

      def current_root_recording
        unless RecordingStudio.features.device_sessions?
          return @current_root_recording ||= fallback_root_recording_for(current_actor)
        end

        @current_root_recording ||= resolve_root_recording_with_device_session
      end

      def current_device_session
        return nil unless RecordingStudio.features.device_sessions?

        RecordingStudio.warn_legacy_feature_use!(
          :device_sessions,
          used_by: "#{self.class.name}#current_device_session"
        )

        @current_device_session ||= RecordingStudio::DeviceSession
                                    .for_actor(current_actor)
                                    .for_device(device_fingerprint)
                                    .first
      end

      def switch_root_recording!(new_root_recording)
        unless RecordingStudio.features.device_sessions?
          @current_root_recording = new_root_recording
          @current_device_session = nil
          return new_root_recording
        end

        switch_root_recording_with_device_session!(new_root_recording)
      end

      # rubocop:disable Metrics/MethodLength
      def device_fingerprint
        return unless RecordingStudio.features.device_sessions?
        return if current_actor.nil?

        cookies.signed[:rs_device_id] ||= {
          value: SecureRandom.uuid,
          expires: 2.years.from_now,
          httponly: true,
          secure: !Rails.env.development?,
          same_site: :lax,
          domain: :all
        }
        cookies.signed[:rs_device_id]
      end
      # rubocop:enable Metrics/MethodLength

      def fallback_root_recording_for(actor)
        return unless actor

        root_id = RecordingStudio::Services::AccessCheck.root_recording_ids_for(actor: actor).first
        return if root_id.blank?

        RecordingStudio::Recording.unscoped.find_by(id: root_id)
      end

      # rubocop:disable Metrics/MethodLength
      def resolve_root_recording_with_device_session
        RecordingStudio.warn_legacy_feature_use!(
          :device_sessions,
          used_by: "#{self.class.name}#current_root_recording"
        )

        result = RecordingStudio::Services::RootRecordingResolver.call(
          actor: current_actor,
          device_fingerprint: device_fingerprint,
          user_agent: request.user_agent
        )

        if result.failure?
          Rails.logger.warn(
            "Failed to resolve root recording: #{result.error} " \
            "(actor_id: #{current_actor&.id}, device_fingerprint: [REDACTED])"
          )
        end

        result.value if result.success?
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def switch_root_recording_with_device_session!(new_root_recording)
        RecordingStudio.warn_legacy_feature_use!(
          :device_sessions,
          used_by: "#{self.class.name}#switch_root_recording!"
        )

        session = RecordingStudio::DeviceSession.resolve(
          actor: current_actor,
          device_fingerprint: device_fingerprint,
          user_agent: request.user_agent
        )

        old_recording_id = session.root_recording_id
        session.switch_to!(new_root_recording)

        Rails.logger.info(
          "Workspace switched: actor_id=#{current_actor.id} actor_type=#{current_actor.class.name} " \
          "from_recording=#{old_recording_id} to_recording=#{new_root_recording.id}"
        )

        @current_root_recording = new_root_recording
        @current_device_session = session
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end
  end
end
