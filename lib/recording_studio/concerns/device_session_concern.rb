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
        session.switch_to!(new_root_recording)
        @current_root_recording = new_root_recording
        @current_device_session = session
      end

      def device_fingerprint
        cookies.signed[:rs_device_id] ||= {
          value: SecureRandom.uuid,
          expires: 10.years.from_now,
          httponly: true,
          secure: Rails.env.production?,
          same_site: :lax
        }
        cookies.signed[:rs_device_id]
      end
    end
  end
end
