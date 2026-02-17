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
        @current_root_recording ||= begin
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
      end

      def current_device_session
        @current_device_session ||= RecordingStudio::DeviceSession
          .for_actor(current_actor)
          .for_device(device_fingerprint)
          .first
      end

      def switch_root_recording!(new_root_recording)
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

      def device_fingerprint
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
    end
  end
end
