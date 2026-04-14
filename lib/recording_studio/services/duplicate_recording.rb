# frozen_string_literal: true

module RecordingStudio
  module Services
    # rubocop:disable Metrics/ClassLength
    class DuplicateRecording
      ACTION = "duplicated"

      def self.call(...)
        new(...).call
      end

      def self.allowed?(...)
        new(...).allowed?
      rescue RecordingStudio::AccessDenied, RecordingStudio::CapabilityDisabled, ArgumentError
        false
      end

      def initialize(recording:, actor:, **options)
        @recording = recording
        @actor = actor
        @impersonator = options[:impersonator]
        @options = normalize_options(**options)
      end

      def call
        RecordingStudio::Recording.transaction do
          lock_required_rows!
          existing_duplicate = find_existing_duplicate
          return handle_idempotency(existing_duplicate) if existing_duplicate

          authorize_duplicate!
          duplicate_recordings!
        end
      end

      def allowed?
        authorize_duplicate!
        true
      end

      private

      attr_reader :actor, :impersonator, :options

      def duplicate_recordings!
        root = source_recording.root_recording || source_recording
        duplicates = {}

        selected_recordings.each do |source|
          duplicates[source.id] = duplicate_recording!(source, root:, duplicates:)
        end

        duplicates.fetch(source_recording.id)
      end

      def authorize_duplicate!
        validate_source_recording!
        assert_duplicable!(source_recording)
        assert_view_access!(source_recording)
        assert_edit_access!(source_parent_recording)
        authorize_descendants!
      end

      def validate_source_recording!
        raise ArgumentError, "actor is required" if actor.nil?
        raise ArgumentError, "root recordings cannot be duplicated" if source_recording.parent_recording_id.nil?
        raise ArgumentError, "trashed recordings cannot be duplicated" if source_recording.trashed_at.present?
      end

      def authorize_descendants!
        selected_recordings.drop(1).each do |recording|
          raise ArgumentError, "trashed descendant recordings cannot be duplicated" if recording.trashed_at.present?

          assert_duplicable!(recording)
          assert_view_access!(recording)
        end
      end

      def assert_duplicable!(recording)
        enabled = RecordingStudio.configuration.capability_enabled?(:duplicable, for_type: recording.recordable_type)
        return if enabled

        raise RecordingStudio::CapabilityDisabled,
              "Capability :duplicable is not enabled for #{recording.recordable_type}"
      end

      def assert_view_access!(recording)
        return if RecordingStudio::Services::AccessCheck.allowed?(actor: actor, recording: recording, role: :view)

        raise RecordingStudio::AccessDenied, "Actor does not have view access on recording #{recording.id}"
      end

      def assert_edit_access!(recording)
        return if RecordingStudio::Services::AccessCheck.allowed?(actor: actor, recording: recording, role: :edit)

        raise RecordingStudio::AccessDenied, "Actor does not have edit access on parent recording #{recording.id}"
      end

      def source_recording
        @source_recording ||= reload_recording(@recording.id)
      end

      def source_parent_recording
        @source_parent_recording ||= begin
          parent_id = source_recording.parent_recording_id
          parent_id ? reload_recording(parent_id) : nil
        end
      end

      def selected_recordings
        @selected_recordings ||= begin
          recordings = [source_recording]
          collect_descendants!(recordings) if options[:include_children]

          recordings
        end
      end

      def collect_descendants!(recordings)
        queue = [source_recording]
        until queue.empty?
          current = queue.shift
          children = child_recordings_for(current)
          recordings.concat(children)
          queue.concat(children)
        end
      end

      def lock_required_rows!
        ids = [source_recording.id, source_parent_recording&.id, *selected_recordings.map(&:id)].compact.uniq.sort
        RecordingStudio::Recording.unscoped.where(id: ids).order(:id).lock.load
        reset_loaded_state!
      end

      def reset_loaded_state!
        @source_recording = nil
        @source_parent_recording = nil
        @selected_recordings = nil
      end

      def find_existing_duplicate
        return if options[:idempotency_key].blank?

        RecordingStudio::Event
          .where(action: ACTION, idempotency_key: options[:idempotency_key])
          .where("metadata @> ?", { source_recording_id: @recording.id }.to_json)
          .order(created_at: :desc)
          .first
      end

      def handle_idempotency(event)
        case RecordingStudio.configuration.idempotency_mode.to_sym
        when :raise
          masked_key = event.idempotency_key.to_s
          masked_key = masked_key.length <= 4 ? "****" : "****#{masked_key[-4, 4]}"
          raise RecordingStudio::IdempotencyError,
                "Duplicate already exists for idempotency key (masked): #{masked_key}"
        else
          event.recording
        end
      end

      def duplicate_parent_for(source, duplicates)
        return source_parent_recording if source == source_recording

        duplicates.fetch(source.parent_recording_id)
      end

      def duplication_metadata_for(source)
        options[:metadata].merge(
          "source_recording_id" => source.id,
          "source_recordable_id" => source.recordable_id,
          "source_recordable_type" => source.recordable_type,
          "source_parent_recording_id" => source.parent_recording_id
        )
      end

      def reload_recording(id)
        RecordingStudio::Recording.unscoped.includes(:recordable, :root_recording, :parent_recording).find(id)
      end

      def duplicate_recording!(source, root:, duplicates:)
        duplicated_recordable = RecordingStudio::RecordableDuplicator.call(source.recordable)
        duplicated_recordable.save!

        attributes = duplicate_event_attributes(source, duplicated_recordable, root:, duplicates:)
        RecordingStudio.record!(**attributes).recording
      end

      def child_recordings_for(recording)
        RecordingStudio::Recording.unscoped
                                  .where(parent_recording_id: recording.id)
                                  .includes(:recordable)
                                  .order(:created_at, :id)
                                  .to_a
      end

      def duplicate_event_attributes(source, duplicated_recordable, root:, duplicates:)
        {
          action: ACTION,
          recordable: duplicated_recordable,
          root_recording: root,
          parent_recording: duplicate_parent_for(source, duplicates),
          actor: actor,
          impersonator: impersonator,
          metadata: duplication_metadata_for(source),
          idempotency_key: source == source_recording ? options[:idempotency_key] : nil
        }
      end

      def normalize_options(metadata: nil, include_children: false, idempotency_key: nil, **)
        {
          metadata: (metadata.presence || {}).deep_stringify_keys,
          include_children: include_children ? true : false,
          idempotency_key: idempotency_key.presence
        }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
